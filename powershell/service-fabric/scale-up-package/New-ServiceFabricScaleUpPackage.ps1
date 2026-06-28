<#
.SYNOPSIS
    Generates a complete Service Fabric primary node type scale-up package by discovering
    the existing cluster topology and cloning the VMSS resource definition.

.DESCRIPTION
    Queries the target Service Fabric cluster and its primary VMSS to auto-discover all
    configuration needed for a reuse-first (same node type) or separate node type scale-up.
    Produces:
      - A replacement VMSS ARM template (whole-object clone with only name/sku/password parameterized)
      - A parameter file with the 4 values that change (name, sku, count, password)
      - A drain script with actual node names and seed-node-aware ordering
      - A cleanup script for stale node state removal
      - A validation script (pre-flight, post-deploy, post-drain, post-cleanup)
      - A customer-facing runbook with cluster-specific details

    Template generation clones the entire raw VMSS resource, resolves ARM expressions,
    strips read-only properties, and parameterizes only what must change. This preserves
    every VMSS property (zones, security profile, NIC config, disk encryption, etc.)
    without maintaining an explicit property list.

    Works in two modes:
      - Live mode (default): queries Azure resources via REST API
      - Export mode (-TemplateExportPath): parses an ARM template export file (no Azure access needed)

.NOTES
    File Name  : New-ServiceFabricScaleUpPackage.ps1
    Author     : jagilber
    Version    : 2.1.0
    Changelog  : 2.1.0 - Split server/client certificate support in generated drain, cleanup,
                          and validation scripts (new -ClientCertThumbprint; -CertThumbprint is
                          the server cert). Derive the TCP ConnectionEndpoint (host:19000) from
                          the management endpoint instead of passing the https management URL to
                          Connect-ServiceFabricCluster -ConnectionEndpoint. Validated end-to-end
                          against a live split-cert cluster (seed migration + cleanup).
                 2.0.1 - PS 5.1 compatibility (removed the unsupported -Depth argument from
                          ConvertFrom-Json calls); guard generated validation script against
                          placeholder resource-group names; resolve and guard ManagementEndpoint
                          from ARM export to avoid cryptic connect failures. Derive
                          ResourceGroupName from the export file name with ID cross-validation.
                 2.0.0 - Whole-object clone approach: template generation clones raw VMSS,
                          parameterizes only name/sku/password. Eliminates property-by-property
                          mapping and 30+ template parameters.
                 1.0.0 - Initial version from case 2605070050002786 generalization

.LINK
    https://learn.microsoft.com/azure/service-fabric/service-fabric-scale-up-primary-node-type

.PARAMETER ResourceGroupName
    The resource group containing the Service Fabric cluster and VMSS.

.PARAMETER ClusterName
    The Service Fabric cluster name. Defaults to ResourceGroupName.

.PARAMETER TargetVmSku
    The target VM SKU for the replacement VMSS (e.g., Standard_D8ads_v5).

.PARAMETER ReplacementVmssName
    Short name for the new VMSS. Maximum 9 characters (Service Fabric constraint).

.PARAMETER OutputPath
    Directory where generated artifacts are written. Created if it does not exist.

.PARAMETER NodeTypeName
    The node type to scale up. Defaults to the primary node type discovered from the cluster.

.PARAMETER InstanceCount
    Instance count for the replacement VMSS. Defaults to the existing VMSS capacity.

.PARAMETER AdminPassword
    SecureString for the replacement VMSS admin password. Prompted interactively if omitted.

.PARAMETER TemplateExportPath
    Path to an ARM template export JSON file. When specified, discovery uses the file
    instead of live Azure queries. Useful when the engineer has no access to the customer subscription.

.PARAMETER ExcludeExtensions
    Extension publisher patterns to exclude from cloning. Defaults to the retired Azure
    Diagnostics extension ('Microsoft.Azure.Diagnostics').

.PARAMETER SeparateNodeType
    When specified, generates a separate node type package instead of the reuse-first path.
    This creates a new node type with its own Load Balancer and requires primary promotion/demotion steps.

.PARAMETER SkipDrainScripts
    When specified, skips generation of drain and cleanup PowerShell scripts.

.EXAMPLE
    .\New-ServiceFabricScaleUpPackage.ps1 -ResourceGroupName 'cpsecureprd-rg' -ClusterName 'cpsecureprd' -TargetVmSku 'Standard_D8ads_v5' -ReplacementVmssName 'cpsfsprd2' -OutputPath '.\scaleup-package'

.EXAMPLE
    .\New-ServiceFabricScaleUpPackage.ps1 -TemplateExportPath '.\customer-export.json' -TargetVmSku 'Standard_D4ads_v5' -ReplacementVmssName 'nt0new' -OutputPath '.\scaleup-package'
#>

[CmdletBinding(DefaultParameterSetName = 'Live', SupportsShouldProcess = $true)]
param(
    [Parameter(ParameterSetName = 'Live', Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(ParameterSetName = 'Live')]
    [string]$ClusterName = $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateLength(1, 9)]
    [string]$ReplacementVmssName,

    [Parameter(Mandatory = $true)]
    [string]$TargetVmSku,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$NodeTypeName,

    [int]$InstanceCount = 0,

    [securestring]$AdminPassword,

    [Parameter(ParameterSetName = 'Export', Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$TemplateExportPath,

    [string[]]$ExcludeExtensions = @('Microsoft.Azure.Diagnostics'),

    [switch]$SeparateNodeType,

    [switch]$SkipDrainScripts
)

$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'auto'

#region classes

class SFTopology {
    [string]$ClusterName
    [string]$ClusterEndpoint
    [string]$ManagementEndpoint
    [string]$ResourceGroupName
    [string]$PrimaryNodeTypeName
    [string]$ExistingVmssName
    [string]$VmSku
    [int]$Capacity
    [string]$IdentityType
    [string]$VnetResourceId
    [string]$SubnetName
    [string]$SubnetPrefix
    [string]$LbName
    [string]$BackendPoolName
    [bool]$HasNatPool
    [string[]]$NatPoolIds
    [string]$KvResourceId
    [string]$CertUrl
    [string]$CertThumbprint
    [string]$DurabilityLevel
    [object]$ImageReference
    [string]$OsDiskType
    [int]$OsDiskSizeGB
    [int]$FaultDomainCount
    [string]$UpgradePolicyMode
    [bool]$Overprovision
    [string]$AdminUsername
    [object[]]$AllExtensions
    [string]$SupportLogStorageAccountName
    [hashtable]$GatewayPorts
    [hashtable]$ApplicationPorts
    [hashtable]$EphemeralPorts
    [object]$Tags
    [bool]$EnableAcceleratedNetworking
    [bool]$EnableAutomaticOSUpgrade
    [object[]]$DataDisks
    [string[]]$ExistingNodeNames
    [string]$NicNamePrefix
    [string]$IpConfigNamePrefix
    [string]$ComputerNamePrefix

    # Raw VMSS resource (ARM-format JSON) - template generation clones this whole object,
    # overrides name/sku/password/extensions, and emits as-is. No property-by-property mapping.
    [object]$RawVmssResource
}

#endregion classes

#region main

function main {
    # ShouldProcess is handled by the script-level CmdletBinding, not this function
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param()
    write-console "New-ServiceFabricScaleUpPackage starting..."
    $error.Clear()

    try {
        if (-not $WhatIfPreference -and -not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            write-console "Created output directory: $OutputPath"
        }

        $topology = $null

        if ($PSCmdlet.ParameterSetName -eq 'Export') {
            write-console "Discovery mode: ARM template export file"
            $topology = Get-TopologyFromExport -exportPath $TemplateExportPath
        }
        else {
            write-console "Discovery mode: live Azure resources"
            $topology = Get-TopologyFromLive -resourceGroupName $ResourceGroupName -clusterName $ClusterName
        }

        if (-not $topology) {
            write-console "Failed to discover cluster topology" -err
            return
        }

        # Apply overrides
        if ($NodeTypeName) {
            write-console "Overriding node type name: $($topology.PrimaryNodeTypeName) -> $NodeTypeName"
            $topology.PrimaryNodeTypeName = $NodeTypeName
        }

        if ($InstanceCount -gt 0) {
            write-console "Overriding instance count: $($topology.Capacity) -> $InstanceCount"
            $topology.Capacity = $InstanceCount
        }

        write-console "`n=== Discovered Topology ===" -foregroundColor Cyan
        write-topology $topology

        # Generate artifacts
        $templatePath = Join-Path $OutputPath 'replacement-vmss.template.json'
        $parameterPath = Join-Path $OutputPath 'replacement-vmss.parameters.json'

        if ($PSCmdlet.ShouldProcess($templatePath, 'Generate ARM template')) {
            write-console "`nGenerating ARM template..." -foregroundColor Cyan
            New-ReplacementTemplate -topology $topology -outputFile $templatePath
        }

        if ($PSCmdlet.ShouldProcess($parameterPath, 'Generate parameter file')) {
            write-console "Generating parameter file..." -foregroundColor Cyan
            New-ReplacementParameters -topology $topology -outputFile $parameterPath
        }

        if (-not $SkipDrainScripts) {
            $drainPath = Join-Path $OutputPath 'Invoke-DrainOldNodes.ps1'
            if ($PSCmdlet.ShouldProcess($drainPath, 'Generate drain script')) {
                write-console "Generating drain script..." -foregroundColor Cyan
                New-DrainScript -topology $topology -outputFile $drainPath
            }

            $cleanupPath = Join-Path $OutputPath 'Remove-StaleNodeState.ps1'
            if ($PSCmdlet.ShouldProcess($cleanupPath, 'Generate cleanup script')) {
                write-console "Generating cleanup script..." -foregroundColor Cyan
                New-CleanupScript -topology $topology -outputFile $cleanupPath
            }

            $validatePath = Join-Path $OutputPath 'Test-ScaleUpReadiness.ps1'
            if ($PSCmdlet.ShouldProcess($validatePath, 'Generate validation script')) {
                write-console "Generating validation script..." -foregroundColor Cyan
                New-ValidationScript -topology $topology -outputFile $validatePath
            }
        }

        $runbookPath = Join-Path $OutputPath 'RUNBOOK.md'
        if ($PSCmdlet.ShouldProcess($runbookPath, 'Generate runbook')) {
            write-console "Generating runbook..." -foregroundColor Cyan
            New-Runbook -topology $topology -outputFile $runbookPath
        }

        if (-not $WhatIfPreference) {
            write-console "`n=== Package generation complete ===" -foregroundColor Green
            write-console "Output directory: $OutputPath"
            write-console "Files generated:"
            Get-ChildItem $OutputPath | ForEach-Object { write-console "  $($_.Name)" }
            write-console "`nReview the parameter file and replace any '<REQUIRED>' placeholders before deployment." -foregroundColor Yellow
        }
    }
    catch [Exception] {
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        return 1
    }
    finally {
        # perform any necessary cleanup
    }
}

#endregion main

#region discovery-live

function Get-TopologyFromLive([string]$resourceGroupName, [string]$clusterName) {
    write-console "Querying cluster: $clusterName in RG: $resourceGroupName"

    if (-not (Get-Module Az.Accounts -ListAvailable)) {
        write-console "Az.Accounts module not available. Install with: Install-Module Az.Accounts (or the full Az module)" -err
        return $null
    }

    if (-not (Get-AzContext)) {
        write-console "Not logged in to Azure. Run Connect-AzAccount first." -err
        return $null
    }

    # Get SF cluster resource
    $clusterResource = Get-AzResource `
        -ResourceGroupName $resourceGroupName `
        -ResourceType 'Microsoft.ServiceFabric/clusters' `
        -Name $clusterName `
        -ExpandProperties `
        -ErrorAction SilentlyContinue

    if (-not $clusterResource) {
        write-console "Cluster '$clusterName' not found in RG '$resourceGroupName'" -err
        return $null
    }

    write-console "Cluster endpoint: $($clusterResource.Properties.ClusterEndpoint)"

    # Find primary node type
    $nodeTypes = @($clusterResource.Properties.NodeTypes)
    $primaryNT = $nodeTypes | Where-Object { $_.IsPrimary -eq $true } | Select-Object -First 1
    if (-not $primaryNT) {
        write-console "No primary node type found in cluster" -err
        return $null
    }

    write-console "Primary node type: $($primaryNT.Name)"

    # Find the VMSS matching the primary node type
    $allVmss = @(Get-AzResource `
            -ResourceGroupName $resourceGroupName `
            -ResourceType 'Microsoft.Compute/virtualMachineScaleSets' `
            -ExpandProperties `
            -ErrorAction SilentlyContinue)

    $primaryVmss = $null
    foreach ($vmss in $allVmss) {
        $sfExt = $vmss.Properties.virtualMachineProfile.extensionProfile.extensions.properties |
            Where-Object { $_.publisher -imatch 'ServiceFabric' }
        if ($sfExt -and $sfExt.settings.nodeTypeRef -ieq $primaryNT.Name -and
            $sfExt.settings.clusterEndpoint -ieq $clusterResource.Properties.ClusterEndpoint) {
            $primaryVmss = $vmss
            break
        }
    }

    if (-not $primaryVmss) {
        write-console "No VMSS found for primary node type '$($primaryNT.Name)'" -err
        return $null
    }

    write-console "Primary VMSS: $($primaryVmss.Name) (SKU: $($primaryVmss.Properties.virtualMachineProfile.storageProfile.imageReference.sku))"

    # Extract networking
    $nicConfigs = $primaryVmss.Properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
    $primaryNic = $nicConfigs | Where-Object { $_.properties.primary -eq $true } | Select-Object -First 1
    if (-not $primaryNic) { $primaryNic = $nicConfigs | Select-Object -First 1 }

    $primaryIpConfig = $primaryNic.properties.ipConfigurations | Select-Object -First 1
    $subnetId = $primaryIpConfig.properties.subnet.id
    $subnetName = $subnetId.Split('/')[-1]
    $vnetId = $subnetId -replace '/subnets/[^/]+$', ''

    # LB backend pool
    $lbPoolIds = @($primaryIpConfig.properties.loadBalancerBackendAddressPools.id)
    $lbName = ''
    $backendPoolName = 'LoadBalancerBEAddressPool'
    if ($lbPoolIds.Count -gt 0 -and $lbPoolIds[0]) {
        $lbSegments = $lbPoolIds[0] -split '/'
        $lbName = $lbSegments[8]
        $backendPoolName = $lbPoolIds[0].Split('/')[-1]
    }

    # NAT pool detection
    $natPoolIds = @()
    if ($primaryIpConfig.properties.loadBalancerInboundNatPools) {
        $natPoolIds = @($primaryIpConfig.properties.loadBalancerInboundNatPools.id)
    }

    # Certificate config
    $secrets = @($primaryVmss.Properties.virtualMachineProfile.osProfile.secrets)
    $kvResourceId = ''
    $certUrl = ''
    if ($secrets.Count -gt 0 -and $secrets[0]) {
        $kvResourceId = $secrets[0].sourceVault.id
        if ($secrets[0].vaultCertificates -and $secrets[0].vaultCertificates.Count -gt 0) {
            $certUrl = $secrets[0].vaultCertificates[0].certificateUrl
        }
    }

    # SF extension settings
    $sfExtProps = $primaryVmss.Properties.virtualMachineProfile.extensionProfile.extensions.properties |
        Where-Object { $_.publisher -imatch 'ServiceFabric' }
    $certThumbprint = ''
    $durabilityLevel = 'Silver'
    if ($sfExtProps) {
        $certThumbprint = $sfExtProps.settings.certificate.thumbprint
        $durabilityLevel = $sfExtProps.settings.durabilityLevel
        if (-not $durabilityLevel) { $durabilityLevel = 'Silver' }
    }

    # All extensions
    $allExtensions = @($primaryVmss.Properties.virtualMachineProfile.extensionProfile.extensions)

    # Image reference
    $imageRef = $primaryVmss.Properties.virtualMachineProfile.storageProfile.imageReference

    # OS disk
    $osDisk = $primaryVmss.Properties.virtualMachineProfile.storageProfile.osDisk
    $osDiskType = 'Standard_LRS'
    $osDiskSizeGB = 0
    if ($osDisk.managedDisk) {
        $osDiskType = $osDisk.managedDisk.storageAccountType
    }
    if ($osDisk.diskSizeGB) {
        $osDiskSizeGB = $osDisk.diskSizeGB
    }

    # Data disks
    $dataDisks = @()
    $_storageProfile = $primaryVmss.Properties.virtualMachineProfile.storageProfile
    if ($_storageProfile -and $_storageProfile.PSObject.Properties['dataDisks'] -and $_storageProfile.dataDisks) {
        $dataDisks = @($_storageProfile.dataDisks)
    }

    # Subnet prefix (requires VNet query)
    $subnetPrefix = ''
    try {
        $vnetRgName = ($vnetId -split '/')[4]
        $vnetName = ($vnetId -split '/')[-1]
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $vnetRgName -Name $vnetName -ErrorAction SilentlyContinue
        if ($vnet) {
            $subnetObj = $vnet.Subnets | Where-Object { $_.Name -eq $subnetName }
            if ($subnetObj) {
                $subnetPrefix = $subnetObj.AddressPrefix
                if ($subnetPrefix -is [array]) { $subnetPrefix = $subnetPrefix[0] }
            }
        }
    }
    catch {
        write-console "Warning: could not query subnet prefix: $($_.Exception.Message)" -foregroundColor Yellow
    }

    # Support log storage account - try to find from cluster diagnosticsStorageAccountConfig
    $supportLogStorage = ''
    if ($clusterResource.Properties.diagnosticsStorageAccountConfig) {
        $storageEndpoint = $clusterResource.Properties.diagnosticsStorageAccountConfig.blobEndpoint
        if ($storageEndpoint) {
            # Extract account name from https://<accountname>.blob.core.windows.net/
            if ($storageEndpoint -match 'https://([^.]+)\.blob') {
                $supportLogStorage = $Matches[1]
            }
        }
        if (-not $supportLogStorage -and $clusterResource.Properties.diagnosticsStorageAccountConfig.storageAccountName) {
            $supportLogStorage = $clusterResource.Properties.diagnosticsStorageAccountConfig.storageAccountName
        }
    }

    # Accelerated networking
    $enableAccelNet = $false
    if ($primaryNic.properties.PSObject.Properties['enableAcceleratedNetworking'] -and $primaryNic.properties.enableAcceleratedNetworking) {
        $enableAccelNet = $primaryNic.properties.enableAcceleratedNetworking
    }

    # Automatic OS upgrade
    $enableAutoOSUpgrade = $false
    if ($primaryVmss.Properties.upgradePolicy.PSObject.Properties['automaticOSUpgradePolicy'] -and $primaryVmss.Properties.upgradePolicy.automaticOSUpgradePolicy) {
        $enableAutoOSUpgrade = [bool]$primaryVmss.Properties.upgradePolicy.automaticOSUpgradePolicy.enableAutomaticOSUpgrade
    }

    # Tags
    $tags = $primaryVmss.Tags

    # Existing node names (best effort)
    $existingNodeNames = @()
    try {
        $instances = Get-AzVmssVM -ResourceGroupName $resourceGroupName -VMScaleSetName $primaryVmss.Name -ErrorAction SilentlyContinue
        if ($instances) {
            $existingNodeNames = @($instances | ForEach-Object {
                    "_$($primaryVmss.Name)_$($_.InstanceId)"
                } | Sort-Object)
        }
    }
    catch {
        write-console "Warning: could not enumerate VMSS instances: $($_.Exception.Message)" -foregroundColor Yellow
        # Fallback: generate names from capacity
        for ($i = 0; $i -lt $primaryVmss.Sku.Capacity; $i++) {
            $existingNodeNames += "_$($primaryVmss.Name)_$i"
        }
    }

    $topology = [SFTopology]@{
        ClusterName                  = $clusterName
        ClusterEndpoint              = $clusterResource.Properties.ClusterEndpoint
        ManagementEndpoint           = $clusterResource.Properties.ManagementEndpoint
        ResourceGroupName            = $resourceGroupName
        PrimaryNodeTypeName          = $primaryNT.Name
        ExistingVmssName             = $primaryVmss.Name
        VmSku                        = $primaryVmss.Sku.Name
        Capacity                     = $primaryVmss.Sku.Capacity
        IdentityType                 = $primaryVmss.Identity.Type
        VnetResourceId               = $vnetId
        SubnetName                   = $subnetName
        SubnetPrefix                 = $subnetPrefix
        LbName                       = $lbName
        BackendPoolName              = $backendPoolName
        HasNatPool                   = ($natPoolIds.Count -gt 0)
        NatPoolIds                   = $natPoolIds
        KvResourceId                 = $kvResourceId
        CertUrl                      = $certUrl
        CertThumbprint               = $certThumbprint
        DurabilityLevel              = $durabilityLevel
        ImageReference               = $imageRef
        OsDiskType                   = $osDiskType
        OsDiskSizeGB                 = $osDiskSizeGB
        FaultDomainCount             = [int]$primaryVmss.Properties.platformFaultDomainCount
        UpgradePolicyMode            = $primaryVmss.Properties.upgradePolicy.mode
        Overprovision                = [bool]$primaryVmss.Properties.overprovision
        AdminUsername                = $primaryVmss.Properties.virtualMachineProfile.osProfile.adminUsername
        AllExtensions                = $allExtensions
        SupportLogStorageAccountName = $supportLogStorage
        GatewayPorts                 = @{
            Tcp  = $primaryNT.ClientConnectionEndpointPort
            Http = $primaryNT.HttpGatewayEndpointPort
        }
        ApplicationPorts             = @{
            Start = $primaryNT.ApplicationPorts.StartPort
            End   = $primaryNT.ApplicationPorts.EndPort
        }
        EphemeralPorts               = @{
            Start = $primaryNT.EphemeralPorts.StartPort
            End   = $primaryNT.EphemeralPorts.EndPort
        }
        Tags                         = $tags
        EnableAcceleratedNetworking  = $enableAccelNet
        EnableAutomaticOSUpgrade     = $enableAutoOSUpgrade
        DataDisks                    = $dataDisks
        ExistingNodeNames            = $existingNodeNames
        NicNamePrefix                = $primaryNic.name
        IpConfigNamePrefix           = $primaryIpConfig.name
        ComputerNamePrefix           = $primaryVmss.Properties.virtualMachineProfile.osProfile.computerNamePrefix
        RawVmssResource              = $null
    }

    # Get the raw VMSS in ARM-native JSON format via REST API
    # (Get-AzResource returns PascalCase SDK objects; REST gives us camelCase ARM-ready JSON)
    try {
        write-console "  Fetching VMSS resource via REST API for template generation..."
        $restResponse = Invoke-AzRestMethod -Path "$($primaryVmss.ResourceId)?api-version=2023-09-01" -Method GET
        if ($restResponse.StatusCode -eq 200) {
            $topology.RawVmssResource = $restResponse.Content | ConvertFrom-Json
        }
        else {
            write-console "  Warning: REST API returned $($restResponse.StatusCode), template generation may be limited" -foregroundColor Yellow
        }
    }
    catch {
        write-console "  Warning: REST API call failed: $($_.Exception.Message)" -foregroundColor Yellow
    }

    return $topology
}

#endregion discovery-live

#region discovery-export

function Get-TopologyFromExport([string]$exportPath) {
    write-console "Parsing ARM template export: $exportPath"
    $template = Get-Content $exportPath -Raw | ConvertFrom-Json

    # Find VMSS resources
    $vmssResources = @($template.resources | Where-Object {
            $_.type -eq 'Microsoft.Compute/virtualMachineScaleSets'
        })

    if ($vmssResources.Count -eq 0) {
        write-console "No VMSS resources found in export" -err
        return $null
    }

    # Find SF cluster resource
    $clusterResource = $template.resources | Where-Object {
        $_.type -eq 'Microsoft.ServiceFabric/clusters'
    } | Select-Object -First 1

    # If no cluster resource in export, try to extract from VMSS SF extension
    $clusterEndpoint = ''
    $managementEndpoint = ''
    $primaryNodeTypeName = ''
    $gatewayPorts = @{ Tcp = 19000; Http = 19080 }
    $appPorts = @{ Start = 20000; End = 30000 }
    $ephPorts = @{ Start = 49152; End = 65534 }

    if ($clusterResource) {
        write-console "Found cluster resource in export"
        $clusterEndpoint = resolve-exportValue $clusterResource.properties.clusterEndpoint $template
        $managementEndpoint = resolve-exportValue $clusterResource.properties.managementEndpoint $template
        $nodeTypes = @($clusterResource.properties.nodeTypes)
        $primaryNT = $nodeTypes | Where-Object { $_.isPrimary -eq $true } | Select-Object -First 1
        if ($primaryNT) {
            $primaryNodeTypeName = $primaryNT.name
            if ($primaryNT.clientConnectionEndpointPort) {
                $gatewayPorts.Tcp = $primaryNT.clientConnectionEndpointPort
            }
            if ($primaryNT.httpGatewayEndpointPort) {
                $gatewayPorts.Http = $primaryNT.httpGatewayEndpointPort
            }
            if ($primaryNT.applicationPorts) {
                $appPorts.Start = $primaryNT.applicationPorts.startPort
                $appPorts.End = $primaryNT.applicationPorts.endPort
            }
            if ($primaryNT.ephemeralPorts) {
                $ephPorts.Start = $primaryNT.ephemeralPorts.startPort
                $ephPorts.End = $primaryNT.ephemeralPorts.endPort
            }
        }
    }

    # Find the primary VMSS (match by SF extension nodeTypeRef or take first)
    $primaryVmss = $null
    foreach ($vmss in $vmssResources) {
        $extensions = @(get-exportExtensions $vmss)
        $sfExt = $extensions | Where-Object {
            $_.properties.publisher -imatch 'ServiceFabric'
        } | Select-Object -First 1

        if ($sfExt) {
            $nodeTypeRef = $sfExt.properties.settings.nodeTypeRef
            # Resolve ARM template expressions to raw value where possible
            $resolvedRef = resolve-exportValue $nodeTypeRef $template

            if ($primaryNodeTypeName -and $resolvedRef -ieq $primaryNodeTypeName) {
                $primaryVmss = $vmss
                $clusterEndpoint = resolve-exportValue $sfExt.properties.settings.clusterEndpoint $template
                break
            }
            elseif (-not $primaryNodeTypeName) {
                # No cluster resource - use first VMSS with SF extension
                $primaryVmss = $vmss
                $primaryNodeTypeName = $resolvedRef
                $clusterEndpoint = resolve-exportValue $sfExt.properties.settings.clusterEndpoint $template
                break
            }
        }
    }

    if (-not $primaryVmss) {
        write-console "No VMSS with Service Fabric extension found in export" -err
        return $null
    }

    $vmssName = resolve-exportValue $primaryVmss.name $template
    write-console "Primary VMSS from export: $vmssName"

    # Extract networking
    $nicConfigs = @($primaryVmss.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations)
    $primaryNic = $nicConfigs | Where-Object { $_.properties.primary -eq $true } | Select-Object -First 1
    if (-not $primaryNic) { $primaryNic = $nicConfigs | Select-Object -First 1 }

    $primaryIpConfig = $primaryNic.properties.ipConfigurations | Select-Object -First 1

    # Subnet
    $subnetId = resolve-exportValue $primaryIpConfig.properties.subnet.id $template
    $subnetName = $subnetId.Split('/')[-1]
    # Extract VNet ID - handle both raw IDs and concat expressions
    $vnetId = $subnetId -replace '/subnets/[^/\]"]+.*$', ''

    # LB backend pool
    $lbName = ''
    $backendPoolName = 'LoadBalancerBEAddressPool'
    $lbPools = @($primaryIpConfig.properties.loadBalancerBackendAddressPools)
    if ($lbPools.Count -gt 0 -and $lbPools[0].id) {
        $lbPoolId = resolve-exportValue $lbPools[0].id $template
        # Parse LB name from resolved path: .../Microsoft.Network/loadBalancers/<name>/...
        if ($lbPoolId -match 'loadBalancers/([^/]+)') {
            $lbName = $Matches[1]
        }
        elseif (($lbPoolId -split '/').Count -gt 8) {
            $lbName = ($lbPoolId -split '/')[8]
        }
        $backendPoolName = $lbPoolId.Split('/')[-1]
    }

    # Fallback: find LB resource directly in export
    if (-not $lbName) {
        $lbResource = $template.resources | Where-Object { $_.type -eq 'Microsoft.Network/loadBalancers' } | Select-Object -First 1
        if ($lbResource) {
            $lbName = resolve-exportValue $lbResource.name $template
            write-console "  LB name from resource: $lbName"
        }
    }

    # NAT pool
    $natPoolIds = @()
    if ($primaryIpConfig.properties.loadBalancerInboundNatPools) {
        $natPoolIds = @($primaryIpConfig.properties.loadBalancerInboundNatPools | ForEach-Object {
                resolve-exportValue $_.id $template
            })
    }

    # Certificate
    $secrets = @($primaryVmss.properties.virtualMachineProfile.osProfile.secrets)
    $kvResourceId = ''
    $certUrl = ''
    if ($secrets.Count -gt 0 -and $secrets[0]) {
        $kvResourceId = resolve-exportValue $secrets[0].sourceVault.id $template
        if ($secrets[0].vaultCertificates -and $secrets[0].vaultCertificates.Count -gt 0) {
            $certUrl = resolve-exportValue $secrets[0].vaultCertificates[0].certificateUrl $template
        }
    }

    # SF extension details
    $allExtensions = @(get-exportExtensions $primaryVmss)
    $sfExtProps = ($allExtensions | Where-Object { $_.properties.publisher -imatch 'ServiceFabric' }).properties
    $certThumbprint = ''
    $durabilityLevel = 'Silver'
    if ($sfExtProps) {
        $certThumbprint = resolve-exportValue $sfExtProps.settings.certificate.thumbprint $template
        $durabilityLevel = $sfExtProps.settings.durabilityLevel
        if (-not $durabilityLevel) { $durabilityLevel = 'Silver' }
    }

    # Image reference
    $imageRef = $primaryVmss.properties.virtualMachineProfile.storageProfile.imageReference

    # OS disk
    $osDisk = $primaryVmss.properties.virtualMachineProfile.storageProfile.osDisk
    $osDiskType = 'Standard_LRS'
    $osDiskSizeGB = 0
    if ($osDisk.managedDisk -and $osDisk.managedDisk.storageAccountType) {
        $osDiskType = $osDisk.managedDisk.storageAccountType
    }
    if ($osDisk.diskSizeGB) { $osDiskSizeGB = $osDisk.diskSizeGB }

    # Data disks
    $dataDisks = @()
    if ($primaryVmss.properties.virtualMachineProfile.storageProfile.dataDisks) {
        $dataDisks = @($primaryVmss.properties.virtualMachineProfile.storageProfile.dataDisks)
    }

    # Support log storage - try cluster diagnosticsStorageAccountConfig
    $supportLogStorage = ''
    if ($clusterResource -and $clusterResource.properties.diagnosticsStorageAccountConfig) {
        # Prefer direct storageAccountName (plain string in most exports)
        if ($clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName) {
            $rawName = $clusterResource.properties.diagnosticsStorageAccountConfig.storageAccountName
            if ($rawName -notmatch '^\[') {
                $supportLogStorage = $rawName
            }
            else {
                $supportLogStorage = resolve-exportValue $rawName $template
            }
        }
        # Fallback: extract from blobEndpoint
        if ((-not $supportLogStorage -or $supportLogStorage -match '^<') -and
            $clusterResource.properties.diagnosticsStorageAccountConfig.blobEndpoint) {
            $blobEndpoint = resolve-exportValue $clusterResource.properties.diagnosticsStorageAccountConfig.blobEndpoint $template
            if ($blobEndpoint -match 'https://([^.]+)\.blob') {
                $supportLogStorage = $Matches[1]
            }
        }
    }

    # Tags
    $tags = $primaryVmss.tags

    # Accelerated networking
    $enableAccelNet = $false
    if ($primaryNic.properties.enableAcceleratedNetworking) {
        $enableAccelNet = [bool]$primaryNic.properties.enableAcceleratedNetworking
    }

    # Auto OS upgrade
    $enableAutoOSUpgrade = $false
    if ($primaryVmss.properties.upgradePolicy.automaticOSUpgradePolicy) {
        $enableAutoOSUpgrade = [bool]$primaryVmss.properties.upgradePolicy.automaticOSUpgradePolicy.enableAutomaticOSUpgrade
    }

    # Admin username
    $adminUsername = resolve-exportValue $primaryVmss.properties.virtualMachineProfile.osProfile.adminUsername $template

    # Generate expected node names from capacity
    $capacity = 5
    if ($primaryVmss.sku.capacity) { $capacity = [int]$primaryVmss.sku.capacity }
    $existingNodeNames = @()
    $computerPrefix = resolve-exportValue $primaryVmss.properties.virtualMachineProfile.osProfile.computerNamePrefix $template
    for ($i = 0; $i -lt $capacity; $i++) {
        $existingNodeNames += "_${vmssName}_$i"
    }

    # Cluster name from export
    $clusterName = ''
    if ($clusterResource) {
        $clusterName = resolve-exportValue $clusterResource.name $template
    }
    elseif ($sfExtProps -and $sfExtProps.settings.clusterEndpoint) {
        # Try to extract cluster GUID from endpoint
        $clusterName = '<cluster-name-from-export>'
    }

    # Management endpoint: prefer the resolved value from the cluster resource.
    # ARM exports don't always carry it, so fall back to a clear placeholder the
    # generated scripts detect and refuse to use unguarded.
    if (-not $managementEndpoint -or $managementEndpoint -match '^\[') {
        $managementEndpoint = '<management-endpoint-from-export>'
    }

    # Resource group: an ARM export does NOT store its own source resource-group
    # name as a property. The portal "Export template" feature names the file
    # '<resourceGroup>_rg_template.json', so derive a candidate from the file name
    # and only trust it when it is cross-referenced by a '/resourceGroups/<name>/'
    # ID inside the template. Otherwise fall back to a placeholder the generated
    # PreFlight checks guard against.
    $resourceGroupName = '<resource-group-from-export>'
    $rgCandidate = [System.IO.Path]::GetFileName($exportPath) -replace '(_rg)?_template\.json$|\.json$', ''
    if ($rgCandidate -and $rgCandidate -match '^[-\w\._\(\)]+$') {
        $exportText = $template | ConvertTo-Json -Depth 50 -Compress
        if ($exportText -match [regex]::Escape("/resourceGroups/$rgCandidate/")) {
            $resourceGroupName = $rgCandidate
        }
    }

    $topology = [SFTopology]@{
        ClusterName                  = $clusterName
        ClusterEndpoint              = $clusterEndpoint
        ManagementEndpoint           = $managementEndpoint
        ResourceGroupName            = $resourceGroupName
        PrimaryNodeTypeName          = $primaryNodeTypeName
        ExistingVmssName             = $vmssName
        VmSku                        = $primaryVmss.sku.name
        Capacity                     = $capacity
        IdentityType                 = if ($primaryVmss.identity) { $primaryVmss.identity.type } else { 'SystemAssigned' }
        VnetResourceId               = $vnetId
        SubnetName                   = $subnetName
        SubnetPrefix                 = '<subnet-prefix-not-in-export>'
        LbName                       = $lbName
        BackendPoolName              = $backendPoolName
        HasNatPool                   = ($natPoolIds.Count -gt 0)
        NatPoolIds                   = $natPoolIds
        KvResourceId                 = $kvResourceId
        CertUrl                      = $certUrl
        CertThumbprint               = $certThumbprint
        DurabilityLevel              = $durabilityLevel
        ImageReference               = $imageRef
        OsDiskType                   = $osDiskType
        OsDiskSizeGB                 = $osDiskSizeGB
        FaultDomainCount             = if ($primaryVmss.properties.platformFaultDomainCount) { [int]$primaryVmss.properties.platformFaultDomainCount } else { 5 }
        UpgradePolicyMode            = if ($primaryVmss.properties.upgradePolicy) { $primaryVmss.properties.upgradePolicy.mode } else { 'Automatic' }
        Overprovision                = if ($null -ne $primaryVmss.properties.overprovision) { [bool]$primaryVmss.properties.overprovision } else { $false }
        AdminUsername                = $adminUsername
        AllExtensions                = $allExtensions
        SupportLogStorageAccountName = $supportLogStorage
        GatewayPorts                 = $gatewayPorts
        ApplicationPorts             = $appPorts
        EphemeralPorts               = $ephPorts
        Tags                         = $tags
        EnableAcceleratedNetworking  = $enableAccelNet
        EnableAutomaticOSUpgrade     = $enableAutoOSUpgrade
        DataDisks                    = $dataDisks
        ExistingNodeNames            = $existingNodeNames
        NicNamePrefix                = $primaryNic.name
        IpConfigNamePrefix           = $primaryIpConfig.name
        ComputerNamePrefix           = $computerPrefix
        RawVmssResource              = $primaryVmss
    }

    return $topology
}

function get-exportExtensions($vmssResource) {
    $extensions = $vmssResource.properties.virtualMachineProfile.extensionProfile.extensions
    if (-not $extensions) { return @() }
    return @($extensions)
}

function resolve-exportValue([string]$value, $template) {
    # Resolves ARM template parameter references, concat, and resourceId expressions.
    # Returns raw value or the original expression if unresolvable.
    if (-not $value) { return $value }

    # Not an ARM expression - return as-is
    if ($value -notmatch '^\[') { return $value }

    # Direct parameter reference: [parameters('paramName')]
    if ($value -match "^\[parameters\('([^']+)'\)\]$") {
        $paramName = $Matches[1]
        if ($null -ne $template.parameters.$paramName.defaultValue) {
            return [string]$template.parameters.$paramName.defaultValue
        }
        return "<parameter:$paramName>"
    }

    # resourceId() expressions - extract parameter names and build a fake resource path
    # Pattern: [resourceId('Type/SubType', parameters('p1'), 'literal', ...)]
    if ($value -match '^\[resourceId\(') {
        $resolved = resolve-armFunctionArgs $value $template
        return $resolved
    }

    # Concat with parameter: [concat(parameters('x'), '/subnets/', parameters('y'))]
    if ($value -match '^\[concat\(') {
        $resolved = resolve-armFunctionArgs $value $template
        return $resolved
    }

    return $value
}

function resolve-armFunctionArgs([string]$expression, $template) {
    # Generalized resolver: replaces all parameters('x') refs with defaults,
    # then attempts to simplify concat/resourceId to a plain string.
    $resolved = $expression

    # Replace all parameters('x') with their default values
    $paramPattern = [regex]"parameters\('([^']+)'\)"
    $paramMatches = $paramPattern.Matches($resolved)
    $allResolved = $true
    foreach ($pm in $paramMatches) {
        $paramName = $pm.Groups[1].Value
        if ($null -ne $template.parameters.$paramName.defaultValue) {
            $defaultVal = [string]$template.parameters.$paramName.defaultValue
            $resolved = $resolved.Replace($pm.Value, "'$defaultVal'")
        }
        else {
            $allResolved = $false
        }
    }

    if (-not $allResolved) {
        # Can't fully resolve - return original expression
        return $expression
    }

    # Try to evaluate resourceId() as a synthetic resource path
    if ($resolved -match "^\[resourceId\(") {
        # Extract arguments: resourceId('Type', 'name1', 'name2', ...)
        $inner = $resolved -replace '^\[resourceId\(', '' -replace '\)\]$', ''
        $funcArgs = @($inner -split "," | ForEach-Object { $_.Trim().Trim("'").Trim('"') })
        if ($funcArgs.Count -ge 2) {
            $resourceType = $funcArgs[0]
            $typeSegments = $resourceType -split '/'
            # Build: /subscriptions/.../providers/Type/name1[/SubType/name2]
            $path = "/providers/$($typeSegments[0])/$($typeSegments[1])/$($funcArgs[1])"
            for ($i = 2; $i -lt $typeSegments.Count -and ($i) -lt $funcArgs.Count; $i++) {
                $path += "/$($typeSegments[$i])/$($funcArgs[$i])"
            }
            return $path
        }
    }

    # Try to simplify concat()
    if ($resolved -match "^\[concat\(") {
        $inner = $resolved -replace '^\[concat\(', '' -replace '\)\]$', ''
        # Split on commas, trim quotes, join
        $parts = @($inner -split "," | ForEach-Object { $_.Trim().Trim("'").Trim('"') })
        return ($parts -join '')
    }

    return $expression
}

#endregion discovery-export

#region template-generation

function New-ReplacementTemplate([SFTopology]$topology, [string]$outputFile) {
    # Clone-whole-object approach: deep-copy the raw VMSS resource, resolve ARM expressions,
    # override only name/sku/password/extensions, emit as template. This captures every VMSS
    # property the schema defines - current and future - without maintaining individual field lists.

    $raw = $topology.RawVmssResource
    if (-not $raw) {
        write-console "No raw VMSS resource available - cannot generate template" -err
        return
    }

    # Deep-copy via JSON round-trip
    $vmss = $raw | ConvertTo-Json -Depth 50 | ConvertFrom-Json

    # For export mode: resolve all ARM expressions ([parameters('x')], [concat(...)], etc.)
    if ($TemplateExportPath) {
        $srcTemplate = Get-Content $TemplateExportPath -Raw | ConvertFrom-Json
        Resolve-ObjectExpressions -obj $vmss -template $srcTemplate
    }

    # Strip read-only / server-side properties that ARM rejects on PUT
    Remove-ArmReadOnlyProperties -obj $vmss

    # === Parameterize the few things that MUST change ===
    # Use Set-ObjectProperty helper since PSCustomObjects from ConvertFrom-Json may lack these keys
    Set-ObjectProperty -obj $vmss -name 'name' -value "[parameters('replacementVmssName')]"
    Set-ObjectProperty -obj $vmss.sku -name 'name' -value "[parameters('replacementVmssSize')]"
    Set-ObjectProperty -obj $vmss.sku -name 'capacity' -value "[parameters('replacementVmssInstanceCount')]"

    $vmProfile = $vmss.properties.virtualMachineProfile
    Set-ObjectProperty -obj $vmProfile.osProfile -name 'computerNamePrefix' -value "[parameters('replacementVmssName')]"
    Set-ObjectProperty -obj $vmProfile.osProfile -name 'adminPassword' -value "[parameters('adminPassword')]"

    # === Fix extensions: exclude retired ones, fix SF protectedSettings ===
    $keptExts = @()
    foreach ($ext in @($vmProfile.extensionProfile.extensions)) {
        $pub = $ext.properties.publisher
        $type = $ext.properties.type

        # Check exclusion list
        $skip = $false
        foreach ($pat in $ExcludeExtensions) {
            if ($pub -imatch [regex]::Escape($pat)) {
                write-console "  Excluding extension: $pub/$type" -foregroundColor Yellow
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        write-console "  Including extension: $pub/$type"

        # SF extension: protectedSettings are NEVER returned from GET/export - must regenerate
        if ($pub -imatch 'ServiceFabric') {
            $storageName = $topology.SupportLogStorageAccountName
            if (-not $storageName -or $storageName -match '^<') { $storageName = '<REQUIRED:supportLogStorageAccountName>' }
            $ext.properties | Add-Member -NotePropertyName 'protectedSettings' -NotePropertyValue ([ordered]@{
                    StorageAccountKey1 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', '$storageName'), '2022-09-01').keys[0].value]"
                    StorageAccountKey2 = "[listKeys(resourceId('Microsoft.Storage/storageAccounts', '$storageName'), '2022-09-01').keys[1].value]"
                }) -Force
        }
        else {
            # Non-SF: protectedSettings are masked in GET/export - clear and note for user
            if ($ext.properties.protectedSettings) {
                $ext.properties | Add-Member -NotePropertyName 'protectedSettings' -NotePropertyValue @{} -Force
            }
        }

        # Remove extension-level read-only properties
        foreach ($roProp in @('provisioningState', 'id')) {
            if ($ext.properties.PSObject.Properties[$roProp]) {
                $ext.properties.PSObject.Properties.Remove($roProp)
            }
        }

        $keptExts += $ext
    }
    $vmProfile.extensionProfile.extensions = $keptExts

    # === Remove dependsOn (references resources not in this template) ===
    if ($vmss.PSObject.Properties['dependsOn']) {
        $vmss.PSObject.Properties.Remove('dependsOn')
    }

    # === Remove inbound NAT pool references from all IP configs ===
    # The replacement VMSS shares the same LB backend pool but CANNOT share the same NAT pool
    # as the existing VMSS - ARM creates per-instance NAT rules named by pool+instanceId and
    # they would collide. The new VMSS doesn't need RDP NAT rules during the scale-up window.
    $nicCfgs = $vmss.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
    foreach ($nic in @($nicCfgs)) {
        foreach ($ipCfg in @($nic.properties.ipConfigurations)) {
            if ($ipCfg.properties.PSObject.Properties['loadBalancerInboundNatPools']) {
                $ipCfg.properties.PSObject.Properties.Remove('loadBalancerInboundNatPools')
                write-console "  Removed loadBalancerInboundNatPools from NIC IP config (NAT pool conflict prevention)"
            }
        }
    }

    # === Remove top-level read-only properties ===
    foreach ($roProp in @('id', 'type', 'apiVersion')) {
        if ($vmss.PSObject.Properties[$roProp]) {
            $vmss.PSObject.Properties.Remove($roProp)
        }
    }

    # === Build the ARM template wrapper with minimal parameters ===
    # Minimum node count for a primary node type depends on durability:
    #   Bronze allows 3; Silver/Gold require 5. Clamp to the durability floor, never below.
    $minNodes = if ($topology.DurabilityLevel -imatch 'Bronze') { 3 } else { 5 }
    $defaultNodes = if ($topology.Capacity -ge $minNodes) { $topology.Capacity } else { $minNodes }
    $armTemplate = [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters     = [ordered]@{
            replacementVmssName          = @{ type = 'string'; maxLength = 9; metadata = @{ description = 'Name for the replacement VMSS (max 9 chars for Service Fabric)' } }
            replacementVmssSize          = @{ type = 'string'; defaultValue = $TargetVmSku; metadata = @{ description = 'VM SKU for the replacement VMSS' } }
            replacementVmssInstanceCount = @{ type = 'int'; defaultValue = $defaultNodes; minValue = $minNodes }
            adminPassword                = @{ type = 'securestring'; metadata = @{ description = 'Admin password for the replacement VMSS' } }
        }
        resources      = @(
            [ordered]@{
                type       = 'Microsoft.Compute/virtualMachineScaleSets'
                apiVersion = '2023-09-01'
                name       = $vmss.name
                location   = if ($vmss.location) { $vmss.location } else { '[resourceGroup().location]' }
            }
        )
    }

    # Merge all remaining VMSS properties onto the resource entry
    $resourceEntry = $armTemplate.resources[0]
    foreach ($prop in $vmss.PSObject.Properties) {
        if ($prop.Name -in @('name', 'location')) { continue }  # already set
        $resourceEntry[$prop.Name] = $prop.Value
    }

    $json = $armTemplate | ConvertTo-Json -Depth 50
    Set-Content -Path $outputFile -Value $json -Encoding UTF8
    write-console "  Template written: $outputFile"
}

function Resolve-ObjectExpressions($obj, $template) {
    # Recursively walk a PSObject tree and resolve ARM template expressions to actual values
    if ($null -eq $obj) { return }

    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in @($obj.PSObject.Properties)) {
            if ($prop.Value -is [string] -and $prop.Value -match '^\[.+\]$') {
                $resolved = resolve-exportValue $prop.Value $template
                if ($resolved -ne $prop.Value -and $resolved -notmatch '^<parameter:') {
                    $prop.Value = $resolved
                }
            }
            elseif ($prop.Value -is [System.Management.Automation.PSCustomObject] -or $prop.Value -is [array]) {
                Resolve-ObjectExpressions -obj $prop.Value -template $template
            }
        }
    }
    elseif ($obj -is [array]) {
        for ($i = 0; $i -lt $obj.Count; $i++) {
            if ($obj[$i] -is [string] -and $obj[$i] -match '^\[.+\]$') {
                $resolved = resolve-exportValue $obj[$i] $template
                if ($resolved -ne $obj[$i] -and $resolved -notmatch '^<parameter:') {
                    $obj[$i] = $resolved
                }
            }
            elseif ($obj[$i] -is [System.Management.Automation.PSCustomObject] -or $obj[$i] -is [array]) {
                Resolve-ObjectExpressions -obj $obj[$i] -template $template
            }
        }
    }
}

function Remove-ArmReadOnlyProperties($obj) {
    # Remove server-side / read-only properties that ARM rejects on PUT
    $readOnlyNames = @('provisioningState', 'uniqueId', 'timeCreated', 'requireGuestProvisionSignal')
    # Top-level resource properties to strip (not inside .properties)
    $topLevelReadOnly = @('etag')

    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        # Remove top-level read-only fields from the resource root
        foreach ($roProp in $topLevelReadOnly) {
            if ($obj.PSObject.Properties[$roProp]) {
                $obj.PSObject.Properties.Remove($roProp)
            }
        }

        # Strip read-only principalId/clientId from userAssignedIdentities values.
        # ARM requires each UAI entry to be an empty object {} on PUT/deployment;
        # the GET response includes principalId and clientId which are read-only.
        if ($obj.PSObject.Properties['userAssignedIdentities'] -and
            $obj.userAssignedIdentities -is [System.Management.Automation.PSCustomObject]) {
            foreach ($key in @($obj.userAssignedIdentities.PSObject.Properties.Name)) {
                $obj.userAssignedIdentities.$key = [PSCustomObject]@{}
            }
        }

        # Remove read-only properties from this object
        foreach ($roProp in $readOnlyNames) {
            if ($obj.PSObject.Properties[$roProp]) {
                $obj.PSObject.Properties.Remove($roProp)
            }
        }

        # Recurse into nested objects
        foreach ($prop in @($obj.PSObject.Properties)) {
            if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
                Remove-ArmReadOnlyProperties -obj $prop.Value
            }
            elseif ($prop.Value -is [array]) {
                foreach ($item in $prop.Value) {
                    if ($item -is [System.Management.Automation.PSCustomObject]) {
                        Remove-ArmReadOnlyProperties -obj $item
                    }
                }
            }
        }
    }
}

function Set-ObjectProperty($obj, [string]$name, $value) {
    # Sets a property on a PSCustomObject, adding it via Add-Member if it doesn't exist.
    # ARM export PSCustomObjects may lack properties like adminPassword that we need to set.
    if ($obj.PSObject.Properties[$name]) {
        $obj.$name = $value
    }
    else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    }
}

function New-ReplacementParameters([SFTopology]$topology, [string]$outputFile) {
    # Bronze durability allows a 3-node primary; Silver/Gold require 5.
    $minNodes = if ($topology.DurabilityLevel -imatch 'Bronze') { 3 } else { 5 }
    $params = [ordered]@{
        replacementVmssName          = @{ value = $ReplacementVmssName }
        replacementVmssSize          = @{ value = $TargetVmSku }
        replacementVmssInstanceCount = @{ value = if ($topology.Capacity -ge $minNodes) { $topology.Capacity } else { $minNodes } }
        adminPassword                = @{ value = '<REQUIRED:adminPassword>' }
    }

    $paramFile = [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters     = $params
    }

    $json = $paramFile | ConvertTo-Json -Depth 20
    Set-Content -Path $outputFile -Value $json -Encoding UTF8
    write-console "  Parameters written: $outputFile"

    # Report any remaining placeholders
    $placeholders = [regex]::Matches($json, '<REQUIRED:[^>]+>')
    if ($placeholders.Count -gt 0) {
        write-console "`n  Placeholders requiring manual input:" -foregroundColor Yellow
        foreach ($ph in $placeholders) {
            write-console "    $($ph.Value)" -foregroundColor Yellow
        }
    }
}

#endregion template-generation

#region script-generation

function New-DrainScript([SFTopology]$topology, [string]$outputFile) {
    $nodeList = if ($topology.ExistingNodeNames.Count -gt 0) {
        ($topology.ExistingNodeNames | ForEach-Object { "'$_'" }) -join ",`n    "
    }
    else {
        "# Could not determine existing node names. Replace with actual node names."
    }
    $tcpPort = if ($topology.GatewayPorts.Tcp) { $topology.GatewayPorts.Tcp } else { 19000 }

    $script = @"
<#
.SYNOPSIS
    Drains old VMSS nodes from Service Fabric cluster '$($topology.ClusterName)'.
    Generated by New-ServiceFabricScaleUpPackage.ps1 on $(Get-Date -Format 'yyyy-MM-dd').

.DESCRIPTION
    Deactivates old VMSS nodes one at a time with RemoveNode intent, waiting for each
    to reach Disabled/Completed before proceeding to the next. Non-seed nodes are drained
    first, then seed nodes.

    Seed drains take approximately 19-23 minutes each. Do not interrupt or force-remove.
#>

[CmdletBinding()]
param(
    [string]`$ManagementEndpoint,
    [string]`$ConnectionEndpoint,
    [string]`$CertThumbprint = '$($topology.CertThumbprint)',
    [string]`$ClientCertThumbprint,
    [int]`$PollIntervalSeconds = 30,
    [int]`$TimeoutMinutes = 45
)

`$ErrorActionPreference = 'Stop'

# Load SF module and connect
`$_sfModulePath = 'C:\Program Files\Microsoft Service Fabric\bin\Fabric\Fabric.Code\ServiceFabric.psd1'
if (-not (Get-Command 'Get-ServiceFabricNode' -ErrorAction SilentlyContinue)) {
    if (Test-Path `$_sfModulePath) { Import-Module `$_sfModulePath -ErrorAction Stop }
    else { throw "ServiceFabric module not found at `$_sfModulePath. Install SF SDK or adjust path." }
}
# The server (cluster) certificate and your local admin client certificate may differ
# (split-cert clusters). -CertThumbprint is the server cert presented by the cluster;
# -ClientCertThumbprint is the cert in CurrentUser\My used to authenticate (defaults to the
# server cert when both are the same).
if (-not `$ClientCertThumbprint) { `$ClientCertThumbprint = `$CertThumbprint }
if (-not `$ManagementEndpoint) { `$ManagementEndpoint = '$($topology.ManagementEndpoint)' }
if (`$ManagementEndpoint -match '^<.*>`$') {
    throw "ManagementEndpoint could not be discovered from the ARM export. Re-run with -ManagementEndpoint <https://cluster.region.cloudapp.azure.com:19080>."
}
# Connect-ServiceFabricCluster -ConnectionEndpoint expects the TCP client endpoint host:$tcpPort,
# NOT the https management URL. Derive it from the management endpoint when not supplied.
if (-not `$ConnectionEndpoint) {
    `$_tcpPort = '$tcpPort'
    if (`$ManagementEndpoint -match '^https?://') { `$ConnectionEndpoint = '{0}:{1}' -f ([uri]`$ManagementEndpoint).Host, `$_tcpPort }
    elseif (`$ManagementEndpoint -match ':\d+`$') { `$ConnectionEndpoint = '{0}:{1}' -f (`$ManagementEndpoint -split ':')[0], `$_tcpPort }
    else { `$ConnectionEndpoint = '{0}:{1}' -f `$ManagementEndpoint, `$_tcpPort }
}
Connect-ServiceFabricCluster -ConnectionEndpoint `$ConnectionEndpoint -KeepAliveIntervalInSec 10 -X509Credential ``
    -ServerCertThumbprint `$CertThumbprint -FindType FindByThumbprint -FindValue `$ClientCertThumbprint ``
    -StoreLocation CurrentUser -StoreName My | Out-Null
Write-Host "Connected to `$ConnectionEndpoint (server cert `$CertThumbprint, client cert `$ClientCertThumbprint)"

# Old VMSS node names to drain
`$oldNodes = @(
    $nodeList
)

function Wait-NodeDrained {
    param([string]`$nodeName, [int]`$timeoutMinutes, [int]`$pollSeconds)

    `$deadline = (Get-Date).AddMinutes(`$timeoutMinutes)
    do {
        `$node = Get-ServiceFabricNode -NodeName `$nodeName
        `$status = `$node.NodeStatus
        `$deactivation = `$node.NodeDeactivationInfo.Status
        Write-Host "[`$(Get-Date -Format 'HH:mm:ss')] `$nodeName : NodeStatus=`$status DeactivationStatus=`$deactivation IsSeedNode=`$(`$node.IsSeedNode)"

        if (`$status -eq 'Disabled' -and `$deactivation -eq 'Completed') {
            Write-Host "`$nodeName drain completed." -ForegroundColor Green
            return `$true
        }
        Start-Sleep -Seconds `$pollSeconds
    } while ((Get-Date) -lt `$deadline)

    Write-Warning "`$nodeName did not complete drain within `$timeoutMinutes minutes. DO NOT force-remove. Contact support."
    return `$false
}

function Wait-ClusterHealthy {
    param([int]`$maxWaitSeconds = 120)
    `$deadline = (Get-Date).AddSeconds(`$maxWaitSeconds)
    do {
        `$health = Get-ServiceFabricClusterHealth
        if (`$health.AggregatedHealthState -eq 'Ok') {
            Write-Host "Cluster health: Ok" -ForegroundColor Green
            return `$true
        }
        Write-Host "Cluster health: `$(`$health.AggregatedHealthState) - waiting..."
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt `$deadline)
    Write-Warning "Cluster health did not return to Ok within `$maxWaitSeconds seconds."
    return `$false
}

# Sort: non-seed nodes first, then seed nodes
Write-Host "Querying current node state..."
`$nodeInfo = `$oldNodes | ForEach-Object {
    `$n = Get-ServiceFabricNode -NodeName `$_
    [PSCustomObject]@{ Name = `$_; IsSeedNode = `$n.IsSeedNode }
}
`$sortedNodes = @(`$nodeInfo | Sort-Object IsSeedNode | Select-Object -ExpandProperty Name)
Write-Host "Drain order: `$(`$sortedNodes -join ', ')"
Write-Host ""

foreach (`$nodeName in `$sortedNodes) {
    Write-Host "=== Deactivating `$nodeName ===" -ForegroundColor Cyan
    Disable-ServiceFabricNode -NodeName `$nodeName -Intent RemoveNode -Force

    `$success = Wait-NodeDrained -nodeName `$nodeName -timeoutMinutes `$TimeoutMinutes -pollSeconds `$PollIntervalSeconds
    if (-not `$success) {
        Write-Error "Drain stalled on `$nodeName. Stopping. Do NOT proceed with VMSS deletion."
        return
    }

    Write-Host "Waiting for cluster health to stabilize..."
    Wait-ClusterHealthy -maxWaitSeconds 180

    Write-Host ""
}

Write-Host "All old nodes drained successfully." -ForegroundColor Green
Write-Host "Verify seed migration:"
Get-ServiceFabricNode | Select-Object NodeName, NodeType, NodeStatus, IsSeedNode | Format-Table -AutoSize
"@

    Set-Content -Path $outputFile -Value $script -Encoding UTF8
    write-console "  Drain script written: $outputFile"
}

function New-CleanupScript([SFTopology]$topology, [string]$outputFile) {
    $nodeList = if ($topology.ExistingNodeNames.Count -gt 0) {
        ($topology.ExistingNodeNames | ForEach-Object { "'$_'" }) -join ",`n    "
    }
    else {
        "# Replace with actual old node names"
    }
    $tcpPort = if ($topology.GatewayPorts.Tcp) { $topology.GatewayPorts.Tcp } else { 19000 }

    $script = @"
<#
.SYNOPSIS
    Removes stale Service Fabric node state after old VMSS deletion.
    Generated by New-ServiceFabricScaleUpPackage.ps1 on $(Get-Date -Format 'yyyy-MM-dd').

.DESCRIPTION
    After the old VMSS is deleted, Service Fabric shows the old nodes as Down/Error.
    This script removes their stale state entries.

    PREREQUISITES:
    - Old VMSS has been deleted.
    - All seeds are on the replacement VMSS.
    - Cluster health was Ok before VMSS deletion.
#>

[CmdletBinding()]
param(
    [string]`$ManagementEndpoint = '$($topology.ManagementEndpoint)',
    [string]`$ConnectionEndpoint,
    [string]`$CertThumbprint = '$($topology.CertThumbprint)',
    [string]`$ClientCertThumbprint,
    [switch]`$WhatIf
)

`$ErrorActionPreference = 'Stop'

# Load SF module and connect
`$_sfModulePath = 'C:\Program Files\Microsoft Service Fabric\bin\Fabric\Fabric.Code\ServiceFabric.psd1'
if (-not (Get-Command 'Get-ServiceFabricNode' -ErrorAction SilentlyContinue)) {
    if (Test-Path `$_sfModulePath) { Import-Module `$_sfModulePath -ErrorAction Stop }
    else { throw "ServiceFabric module not found at `$_sfModulePath. Install SF SDK or adjust path." }
}
# Split-cert support: -CertThumbprint is the server cert; -ClientCertThumbprint is the local
# CurrentUser\My client cert (defaults to the server cert when both are the same).
if (-not `$ClientCertThumbprint) { `$ClientCertThumbprint = `$CertThumbprint }
if (`$ManagementEndpoint -match '^<.*>`$') {
    throw "ManagementEndpoint could not be discovered from the ARM export. Re-run with -ManagementEndpoint <https://cluster.region.cloudapp.azure.com:19080>."
}
# Connect-ServiceFabricCluster -ConnectionEndpoint expects host:$tcpPort, not the https URL.
if (-not `$ConnectionEndpoint) {
    `$_tcpPort = '$tcpPort'
    if (`$ManagementEndpoint -match '^https?://') { `$ConnectionEndpoint = '{0}:{1}' -f ([uri]`$ManagementEndpoint).Host, `$_tcpPort }
    elseif (`$ManagementEndpoint -match ':\d+`$') { `$ConnectionEndpoint = '{0}:{1}' -f (`$ManagementEndpoint -split ':')[0], `$_tcpPort }
    else { `$ConnectionEndpoint = '{0}:{1}' -f `$ManagementEndpoint, `$_tcpPort }
}
Connect-ServiceFabricCluster -ConnectionEndpoint `$ConnectionEndpoint -KeepAliveIntervalInSec 10 -X509Credential ``
    -ServerCertThumbprint `$CertThumbprint -FindType FindByThumbprint -FindValue `$ClientCertThumbprint ``
    -StoreLocation CurrentUser -StoreName My | Out-Null
Write-Host "Connected to `$ConnectionEndpoint (server cert `$CertThumbprint, client cert `$ClientCertThumbprint)"

`$oldNodes = @(
    $nodeList
)

foreach (`$nodeName in `$oldNodes) {
    `$node = Get-ServiceFabricNode -NodeName `$nodeName -ErrorAction SilentlyContinue
    if (-not `$node) {
        Write-Host "`$nodeName : already removed" -ForegroundColor DarkGray
        continue
    }

    if (`$node.NodeStatus -notin @('Down', 'Disabled', 'Invalid')) {
        Write-Warning "`$nodeName is still `$(`$node.NodeStatus) - skipping. Only remove Down/Disabled/Invalid nodes."
        continue
    }

    if (`$WhatIf) {
        Write-Host "[WhatIf] Would remove node state: `$nodeName (Status: `$(`$node.NodeStatus))" -ForegroundColor Yellow
    }
    else {
        Write-Host "Removing node state: `$nodeName (Status: `$(`$node.NodeStatus))"
        Remove-ServiceFabricNodeState -NodeName `$nodeName -Force
    }
}

Write-Host ""
Write-Host "Remaining nodes:"
Get-ServiceFabricNode | Select-Object NodeName, NodeType, NodeStatus, IsSeedNode | Format-Table -AutoSize
Write-Host ""
Get-ServiceFabricClusterHealth
"@

    Set-Content -Path $outputFile -Value $script -Encoding UTF8
    write-console "  Cleanup script written: $outputFile"
}

function New-ValidationScript([SFTopology]$topology, [string]$outputFile) {
    $tcpPort = if ($topology.GatewayPorts.Tcp) { $topology.GatewayPorts.Tcp } else { 19000 }
    # Expected replacement node count, baked so PostDrain/PostCleanup thresholds match the
    # actual scale-up size instead of a hardcoded value. Mirrors the template's instance-count
    # default: the discovered capacity, clamped to the durability floor (Bronze 3, else 5).
    $minNodes = if ($topology.DurabilityLevel -imatch 'Bronze') { 3 } else { 5 }
    $expectedNodes = if ($topology.Capacity -ge $minNodes) { $topology.Capacity } else { $minNodes }
    $script = @"
<#
.SYNOPSIS
    Pre-flight and post-step validation for Service Fabric scale-up.
    Generated by New-ServiceFabricScaleUpPackage.ps1 on $(Get-Date -Format 'yyyy-MM-dd').
#>

[CmdletBinding()]
param(
    [ValidateSet('PreFlight', 'PostDeploy', 'PostDrain', 'PostCleanup')]
    [string]`$Phase = 'PreFlight',

    [string]`$ResourceGroupName = '$($topology.ResourceGroupName)',
    [string]`$ClusterName = '$($topology.ClusterName)',
    [string]`$ReplacementVmssName = '$ReplacementVmssName',
    [string]`$TargetVmSku = '$TargetVmSku',
    [int]`$ExpectedNodeCount = $expectedNodes,
    [string]`$ManagementEndpoint = '$($topology.ManagementEndpoint)',
    [string]`$ConnectionEndpoint,
    [string]`$CertThumbprint = '$($topology.CertThumbprint)',
    [string]`$ClientCertThumbprint
)

`$ErrorActionPreference = 'Stop'
`$pass = 0
`$fail = 0

# Load SF module if cmdlets not available. Try the default SDK install path first,
# then fall back to importing 'ServiceFabric' by name (resolved via PSModulePath).
`$_sfModulePath = 'C:\Program Files\Microsoft Service Fabric\bin\Fabric\Fabric.Code\ServiceFabric.psd1'
if (-not (Get-Command 'Get-ServiceFabricNode' -ErrorAction SilentlyContinue)) {
    if (Test-Path `$_sfModulePath) { Import-Module `$_sfModulePath -ErrorAction SilentlyContinue }
    else { Import-Module ServiceFabric -ErrorAction SilentlyContinue }
}
# Track whether the Service Fabric cmdlets are usable so the post-deploy / drain / cleanup
# phases can SKIP (rather than crash with 'term not recognized') when the SF SDK is absent.
`$sfAvailable = `$null -ne (Get-Command 'Get-ServiceFabricNode' -ErrorAction SilentlyContinue)
if (-not `$sfAvailable -and `$Phase -ne 'PreFlight') {
    Write-Host "  [WARN] Service Fabric module not found (looked for `$_sfModulePath and 'ServiceFabric' on PSModulePath). SF node/health checks will be skipped. Install the Service Fabric SDK to enable them." -ForegroundColor Yellow
}
# Connect if SF cmdlets are available (not needed for PreFlight which uses Az module only)
if (`$sfAvailable -and (Get-Command 'Connect-ServiceFabricCluster' -ErrorAction SilentlyContinue) -and `$Phase -ne 'PreFlight') {
    if (`$ManagementEndpoint -match '^<.*>`$') {
        throw "ManagementEndpoint could not be discovered from the ARM export. Re-run with -ManagementEndpoint <https://cluster.region.cloudapp.azure.com:19080> for the '`$Phase' phase."
    }
    # Split-cert support: -CertThumbprint is the server cert; -ClientCertThumbprint is the local
    # CurrentUser\My client cert (defaults to the server cert when both are the same).
    if (-not `$ClientCertThumbprint) { `$ClientCertThumbprint = `$CertThumbprint }
    # Connect-ServiceFabricCluster -ConnectionEndpoint expects host:$tcpPort, not the https URL.
    if (-not `$ConnectionEndpoint) {
        `$_tcpPort = '$tcpPort'
        if (`$ManagementEndpoint -match '^https?://') { `$ConnectionEndpoint = '{0}:{1}' -f ([uri]`$ManagementEndpoint).Host, `$_tcpPort }
        elseif (`$ManagementEndpoint -match ':\d+`$') { `$ConnectionEndpoint = '{0}:{1}' -f (`$ManagementEndpoint -split ':')[0], `$_tcpPort }
        else { `$ConnectionEndpoint = '{0}:{1}' -f `$ManagementEndpoint, `$_tcpPort }
    }
    Connect-ServiceFabricCluster -ConnectionEndpoint `$ConnectionEndpoint -KeepAliveIntervalInSec 10 -X509Credential ``
        -ServerCertThumbprint `$CertThumbprint -FindType FindByThumbprint -FindValue `$ClientCertThumbprint ``
        -StoreLocation CurrentUser -StoreName My | Out-Null
    Write-Host "Connected to `$ConnectionEndpoint (server cert `$CertThumbprint, client cert `$ClientCertThumbprint)"
}

function Assert-Check(`$name, `$condition, `$detail) {
    if (`$condition) {
        Write-Host "  [PASS] `$name" -ForegroundColor Green
        `$script:pass++
    }
    else {
        Write-Host "  [FAIL] `$name : `$detail" -ForegroundColor Red
        `$script:fail++
    }
}

switch (`$Phase) {
    'PreFlight' {
        Write-Host "=== Pre-Flight Checks ===" -ForegroundColor Cyan

        # Azure connectivity
        `$ctx = Get-AzContext
        Assert-Check 'Azure login' (`$null -ne `$ctx) 'Run Connect-AzAccount'

        # Validate required inputs. Export-mode discovery cannot infer the resource
        # group, so it injects a '<...>' placeholder. Passing that to Az cmdlets trips
        # their ValidatePattern and produces a cryptic error, so guard it here.
        `$rgPattern = '^[-\w\._\(\)]+`$'
        `$rgValid = `$ResourceGroupName -match `$rgPattern
        if (-not `$rgValid) {
            Write-Host "  [WARN] ResourceGroupName '`$ResourceGroupName' is not set or invalid. Re-run with -ResourceGroupName <name> to enable cluster and quota checks." -ForegroundColor Yellow
        }

        # Cluster state
        if (`$rgValid -and (`$ClusterName -match `$rgPattern)) {
            `$cluster = Get-AzServiceFabricCluster -ResourceGroupName `$ResourceGroupName -Name `$ClusterName -ErrorAction SilentlyContinue
            Assert-Check 'Cluster exists' (`$null -ne `$cluster) "Cluster `$ClusterName not found in RG `$ResourceGroupName"
            if (`$cluster) {
                Assert-Check 'Cluster state Ready' (`$cluster.ClusterState -eq 'Ready') "State: `$(`$cluster.ClusterState)"
                Assert-Check 'Cluster provisioning Succeeded' (`$cluster.ProvisioningState -eq 'Succeeded') "State: `$(`$cluster.ProvisioningState)"
            }
        }
        else {
            Write-Host "  [SKIP] Cluster checks - provide valid -ResourceGroupName and -ClusterName" -ForegroundColor Yellow
        }

        # Quota check
        if (`$rgValid) {
            try {
                `$location = (Get-AzResourceGroup -Name `$ResourceGroupName -ErrorAction Stop).Location
                `$usage = Get-AzVMUsage -Location `$location | Where-Object { `$_.Name.Value -eq 'cores' }
                `$remaining = `$usage.Limit - `$usage.CurrentValue
                Assert-Check "VM core quota (remaining: `$remaining)" (`$remaining -ge 20) "Only `$remaining cores remaining"
            }
            catch {
                Write-Host "  [WARN] Could not check quota: `$(`$_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  [SKIP] Quota check - provide valid -ResourceGroupName" -ForegroundColor Yellow
        }
    }
    'PostDeploy' {
        Write-Host "=== Post-Deploy Checks ===" -ForegroundColor Cyan

        # Distinguish a genuinely-missing VMSS from an errored lookup (wrong subscription
        # context, wrong resource group, auth/throttling). -ErrorAction SilentlyContinue
        # would collapse all of these into a single, misleading 'not found'.
        `$vmss = `$null
        try {
            `$vmss = Get-AzVmss -ResourceGroupName `$ResourceGroupName -VMScaleSetName `$ReplacementVmssName -ErrorAction Stop
            Assert-Check 'Replacement VMSS exists' (`$null -ne `$vmss) "VMSS '`$ReplacementVmssName' not found in RG '`$ResourceGroupName'"
        }
        catch {
            if (`$_.Exception.Message -match 'NotFound|ResourceNotFound|was not found|could not be found') {
                Assert-Check 'Replacement VMSS exists' `$false "VMSS '`$ReplacementVmssName' not found in RG '`$ResourceGroupName'. Verify -ResourceGroupName and the active subscription (Get-AzContext)."
            }
            else {
                Assert-Check 'Replacement VMSS lookup' `$false "Get-AzVmss failed for '`$ReplacementVmssName' in RG '`$ResourceGroupName': `$(`$_.Exception.Message)"
            }
        }
        if (`$vmss) {
            Assert-Check 'VMSS provisioning succeeded' (`$vmss.ProvisioningState -eq 'Succeeded') "State: `$(`$vmss.ProvisioningState)"
            Assert-Check "VMSS SKU is `$TargetVmSku" (`$vmss.Sku.Name -eq `$TargetVmSku) "SKU: `$(`$vmss.Sku.Name)"
        }

        if (`$sfAvailable) {
            Write-Host "`nService Fabric node state:"
            Get-ServiceFabricNode | Select-Object NodeName, NodeType, NodeStatus, IsSeedNode | Format-Table -AutoSize
        }
        else {
            Write-Host "  [SKIP] Service Fabric node state - SF module not available" -ForegroundColor Yellow
        }
    }
    'PostDrain' {
        Write-Host "=== Post-Drain Checks ===" -ForegroundColor Cyan

        if (-not `$sfAvailable) {
            Write-Host "  [SKIP] Post-drain checks require the Service Fabric module, which is not available." -ForegroundColor Yellow
        }
        else {
            `$nodes = Get-ServiceFabricNode
            `$upNodes = @(`$nodes | Where-Object { `$_.NodeStatus -eq 'Up' })
            `$seedNodes = @(`$nodes | Where-Object { `$_.IsSeedNode -eq `$true -and `$_.NodeStatus -eq 'Up' })
            `$disabledNodes = @(`$nodes | Where-Object { `$_.NodeStatus -eq 'Disabled' })

            Assert-Check 'Replacement nodes are Up' (`$upNodes.Count -ge `$ExpectedNodeCount) "Only `$(`$upNodes.Count) of `$ExpectedNodeCount Up nodes"
            Assert-Check 'Seeds on replacement VMSS' (`$seedNodes.Count -ge [math]::Min(3, `$ExpectedNodeCount)) "Only `$(`$seedNodes.Count) active seed nodes"

            `$health = Get-ServiceFabricClusterHealth
            Assert-Check 'Cluster health Ok' (`$health.AggregatedHealthState -eq 'Ok') "Health: `$(`$health.AggregatedHealthState)"

            Write-Host "`nNode summary:"
            `$nodes | Select-Object NodeName, NodeType, NodeStatus, IsSeedNode | Format-Table -AutoSize
        }
    }
    'PostCleanup' {
        Write-Host "=== Post-Cleanup Checks ===" -ForegroundColor Cyan

        if (-not `$sfAvailable) {
            Write-Host "  [SKIP] Post-cleanup checks require the Service Fabric module, which is not available." -ForegroundColor Yellow
        }
        else {
            `$nodes = Get-ServiceFabricNode
            `$allUp = @(`$nodes | Where-Object { `$_.NodeStatus -eq 'Up' })
            `$downNodes = @(`$nodes | Where-Object { `$_.NodeStatus -notin @('Up') })

            Assert-Check 'All remaining nodes are Up' (`$downNodes.Count -eq 0) "`$(`$downNodes.Count) non-Up nodes remain"
            Assert-Check "At least `$ExpectedNodeCount healthy nodes" (`$allUp.Count -ge `$ExpectedNodeCount) "Only `$(`$allUp.Count) of `$ExpectedNodeCount Up nodes"

            `$health = Get-ServiceFabricClusterHealth
            Assert-Check 'Cluster health Ok' (`$health.AggregatedHealthState -eq 'Ok') "Health: `$(`$health.AggregatedHealthState)"

            Write-Host "`nFinal state:"
            `$nodes | Select-Object NodeName, NodeType, NodeStatus, IsSeedNode | Format-Table -AutoSize
        }
    }
}

Write-Host "``n--- Results: `$pass passed, `$fail failed ---" -ForegroundColor `$(if (`$fail -eq 0) { 'Green' } else { 'Red' })
"@

    Set-Content -Path $outputFile -Value $script -Encoding UTF8
    write-console "  Validation script written: $outputFile"
}

function New-Runbook([SFTopology]$topology, [string]$outputFile) {
    $natWarning = ''
    if ($topology.HasNatPool) {
        $natWarning = @"

### NAT Pool Warning

The existing VMSS has inbound NAT pool bindings. The replacement VMSS **must not** share the same
NAT pool (causes ``InboundNatRuleInUse`` errors). The generated template includes a separate
``inboundNatPoolName`` parameter - create a new NAT pool on the same Load Balancer with a different
port range before deployment, or omit NAT access for the replacement VMSS.
"@
    }

    $dataDiskNote = ''
    if ($topology.DataDisks.Count -gt 0) {
        $dataDiskNote = @"

### Data Disks

The existing VMSS has $($topology.DataDisks.Count) data disk(s) attached. These are replicated in the generated
template. Verify that data disk sizes and storage account types match your requirements.
"@
    }

    $extensionList = ($topology.AllExtensions | ForEach-Object {
            $pub = $_.properties.publisher
            $type = $_.properties.type
            $excluded = $false
            foreach ($pattern in $ExcludeExtensions) {
                if ($pub -imatch [regex]::Escape($pattern)) { $excluded = $true; break }
            }
            $status = if ($excluded) { 'EXCLUDED' } else { 'cloned' }
            "| ``$pub`` | ``$type`` | $status |"
        }) -join "`n"

    $nodeNameList = ($topology.ExistingNodeNames | ForEach-Object { "- ``$_``" }) -join "`n"

    $runbook = @"
# Scale-Up Runbook - $($topology.ClusterName)

Generated by ``New-ServiceFabricScaleUpPackage.ps1`` on $(Get-Date -Format 'yyyy-MM-dd').

## Cluster Topology

| Property | Value |
|---|---|
| Cluster name | ``$($topology.ClusterName)`` |
| Resource group | ``$($topology.ResourceGroupName)`` |
| Management endpoint | ``$($topology.ManagementEndpoint)`` |
| Primary node type | ``$($topology.PrimaryNodeTypeName)`` |
| Existing VMSS | ``$($topology.ExistingVmssName)`` |
| Current VM SKU | ``$($topology.VmSku)`` |
| Target VM SKU | ``$TargetVmSku`` |
| Instance count | $($topology.Capacity) |
| Durability | $($topology.DurabilityLevel) |
| Identity | $($topology.IdentityType) |
| Load Balancer | ``$($topology.LbName)`` |
| Backend pool | ``$($topology.BackendPoolName)`` |
| Subnet | ``$($topology.SubnetName)`` |
| OS image | ``$($topology.ImageReference.publisher)/$($topology.ImageReference.offer)/$($topology.ImageReference.sku)`` |
| Gateway ports | TCP: $($topology.GatewayPorts.Tcp), HTTP: $($topology.GatewayPorts.Http) |
| Application ports | $($topology.ApplicationPorts.Start)-$($topology.ApplicationPorts.End) |
| NAT pool present | $($topology.HasNatPool) |
| Data disks | $($topology.DataDisks.Count) |

## Extensions Discovered

| Publisher | Type | Status |
|---|---|---|
$extensionList

## Existing Nodes (drain targets)

$nodeNameList
$natWarning
$dataDiskNote

## Template Sanitization

The generated ARM template has been cleaned of properties that would cause deployment failures:

- **Read-only properties** stripped: ``provisioningState``, ``uniqueId``, ``timeCreated``, ``requireGuestProvisionSignal``, ``etag``
- **User-assigned identity values** reset to ``{}`` (ARM GET returns read-only ``principalId``/``clientId``; PUT requires empty objects)
- **Inbound NAT pool references** removed from NIC IP configs (replacement VMSS cannot share NAT pools with existing VMSS — causes ``InboundNatRuleInUse`` collision)
- **dependsOn** removed (references resources not in the standalone template)
- **Excluded extensions** stripped (e.g. ``IaaSDiagnostics``) per ``-ExcludeExtensions``

## Procedure

### 1. Pre-Flight

``````powershell
.\Test-ScaleUpReadiness.ps1 -Phase PreFlight
``````

Review the parameter file ``replacement-vmss.parameters.json`` and replace any ``<REQUIRED:...>`` placeholders.

### 2. Deploy Replacement VMSS

``````powershell
Test-AzResourceGroupDeployment ``
    -ResourceGroupName '$($topology.ResourceGroupName)' ``
    -TemplateFile '.\replacement-vmss.template.json' ``
    -TemplateParameterFile '.\replacement-vmss.parameters.json' ``
    -Verbose

New-AzResourceGroupDeployment ``
    -ResourceGroupName '$($topology.ResourceGroupName)' ``
    -Name 'add-replacement-vmss' ``
    -TemplateFile '.\replacement-vmss.template.json' ``
    -TemplateParameterFile '.\replacement-vmss.parameters.json' ``
    -Mode Incremental ``
    -Verbose
``````

### 3. Validate Deployment

``````powershell
.\Test-ScaleUpReadiness.ps1 -Phase PostDeploy
``````

Confirm new VMSS nodes appear under node type ``$($topology.PrimaryNodeTypeName)`` as ``Up``.

### 4. Drain Old Nodes

``````powershell
.\Invoke-DrainOldNodes.ps1
``````

This drains nodes one at a time. Seed drains take ~19-23 minutes each. Do not interrupt.

### 5. Validate Drain

``````powershell
.\Test-ScaleUpReadiness.ps1 -Phase PostDrain
``````

All seeds must be on replacement VMSS nodes. All old nodes must be ``Disabled``/``Completed``.

### 6. Delete Old VMSS

Only after all drain and health gates pass:

``````powershell
Remove-AzVmss -ResourceGroupName '$($topology.ResourceGroupName)' -VMScaleSetName '$($topology.ExistingVmssName)' -Force
``````

### 7. Clean Up Stale Node State

``````powershell
.\Remove-StaleNodeState.ps1
``````

### 8. Final Validation

``````powershell
.\Test-ScaleUpReadiness.ps1 -Phase PostCleanup
``````

## Fallback

If same-node-type seed replacement stalls or produces unexpected behavior, stop and use the
separate-node-type pattern: add a new node type with its own VMSS, promote it to primary,
demote the old node type, then remove it. This remains the Microsoft Learn-aligned approach.
"@

    Set-Content -Path $outputFile -Value $runbook -Encoding UTF8
    write-console "  Runbook written: $outputFile"
}

#endregion script-generation

#region utility

function write-topology([SFTopology]$topology) {
    $props = @(
        ,@('Cluster', $topology.ClusterName)
        ,@('ClusterEndpoint', $topology.ClusterEndpoint)
        ,@('ManagementEndpoint', $topology.ManagementEndpoint)
        ,@('ResourceGroup', $topology.ResourceGroupName)
        ,@('PrimaryNodeType', $topology.PrimaryNodeTypeName)
        ,@('ExistingVMSS', $topology.ExistingVmssName)
        ,@('CurrentSKU', $topology.VmSku)
        ,@('Capacity', $topology.Capacity)
        ,@('Identity', $topology.IdentityType)
        ,@('VNet', $topology.VnetResourceId)
        ,@('Subnet', "$($topology.SubnetName) ($($topology.SubnetPrefix))")
        ,@('LoadBalancer', $topology.LbName)
        ,@('BackendPool', $topology.BackendPoolName)
        ,@('HasNatPool', $topology.HasNatPool)
        ,@('KeyVault', $topology.KvResourceId)
        ,@('CertThumbprint', $topology.CertThumbprint)
        ,@('Durability', $topology.DurabilityLevel)
        ,@('Image', "$($topology.ImageReference.publisher)/$($topology.ImageReference.offer)/$($topology.ImageReference.sku):$($topology.ImageReference.version)")
        ,@('OsDisk', "$($topology.OsDiskType) $(if ($topology.OsDiskSizeGB -gt 0) { "($($topology.OsDiskSizeGB)GB)" })")
        ,@('DataDisks', $topology.DataDisks.Count)
        ,@('FaultDomains', $topology.FaultDomainCount)
        ,@('UpgradePolicy', $topology.UpgradePolicyMode)
        ,@('Overprovision', $topology.Overprovision)
        ,@('AcceleratedNet', $topology.EnableAcceleratedNetworking)
        ,@('AutoOSUpgrade', $topology.EnableAutomaticOSUpgrade)
        ,@('AdminUser', $topology.AdminUsername)
        ,@('SupportLogStorage', $topology.SupportLogStorageAccountName)
        ,@('GatewayPorts', "TCP:$($topology.GatewayPorts.Tcp) HTTP:$($topology.GatewayPorts.Http)")
        ,@('ApplicationPorts', "$($topology.ApplicationPorts.Start)-$($topology.ApplicationPorts.End)")
        ,@('EphemeralPorts', "$($topology.EphemeralPorts.Start)-$($topology.EphemeralPorts.End)")
        ,@('Extensions', $topology.AllExtensions.Count)
        ,@('ExistingNodes', $topology.ExistingNodeNames.Count)
    )

    foreach ($prop in $props) {
        write-console ("  {0,-20} {1}" -f "$($prop[0]):", $prop[1])
    }

    if ($topology.AllExtensions.Count -gt 0) {
        write-console "`n  Extensions:"
        foreach ($ext in $topology.AllExtensions) {
            write-console "    $($ext.properties.publisher) / $($ext.properties.type)"
        }
    }
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (-not $message) { return }
    if ($message.GetType().Name -ine 'string') {
        $message = $message | ConvertTo-Json -Depth 10
    }

    if ($verbose) {
        Write-Verbose $message
    }
    else {
        Write-Host $message -ForegroundColor $foregroundColor
    }

    if ($warn) {
        Write-Warning $message
    }
    elseif ($err) {
        Write-Error $message
        throw
    }
}

#endregion utility

main
