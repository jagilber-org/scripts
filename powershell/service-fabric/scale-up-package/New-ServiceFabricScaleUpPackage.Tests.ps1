#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for New-ServiceFabricScaleUpPackage.ps1
.DESCRIPTION
    Tests export-mode package generation, template structure, parameter files,
    drain script ordering, read-only field stripping, WhatIf support, and
    ARM expression resolution.

    Creates deterministic ARM export fixtures from the repository-owned base
    cluster template so the suite can run without Azure or private case files.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'New-ServiceFabricScaleUpPackage.ps1'
    $script:BaseTemplate = Join-Path $PSScriptRoot 'base-cluster.template.json'
    $script:OutputBase = Join-Path ([System.IO.Path]::GetTempPath()) "pester-sf-scaleup-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    $script:FixtureBase = Join-Path $script:OutputBase 'fixtures'
    $script:ProdExport = Join-Path $script:FixtureBase 'demo-sf-rg_rg_template.json'
    $script:DevExport = Join-Path $script:FixtureBase 'demo-sf-dev_rg_template.json'
    $script:TestCertThumbprint = '0' * 40

    function New-TestExport {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory)]
            [string]$ClusterName,

            [Parameter(Mandatory)]
            [string]$NodeTypeName,

            [Parameter(Mandatory)]
            [int]$Capacity,

            [Parameter(Mandatory)]
            [string]$Location,

            [Parameter(Mandatory)]
            [string]$ImageSku,

            [Parameter(Mandatory)]
            [string]$DurabilityLevel
        )

        $template = Get-Content $script:BaseTemplate -Raw | ConvertFrom-Json
        $vmss = $template.resources |
            Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachineScaleSets' } |
            Select-Object -First 1
        $cluster = $template.resources |
            Where-Object { $_.type -eq 'Microsoft.ServiceFabric/clusters' } |
            Select-Object -First 1
        $resourcePrefix = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$ResourceGroupName/providers"

        $vmss.name = $NodeTypeName
        $vmss.location = $Location
        $vmss.sku.name = 'Standard_DS4_v2'
        $vmss.sku.capacity = $Capacity
        $vmss.tags.clusterName = $ClusterName
        $vmss.properties | Add-Member -NotePropertyName singlePlacementGroup -NotePropertyValue $true -Force
        $vmss.properties | Add-Member -NotePropertyName platformFaultDomainCount -NotePropertyValue 5 -Force
        $vmss | Add-Member -NotePropertyName identity -NotePropertyValue ([pscustomobject]@{ type = 'SystemAssigned' }) -Force

        $profile = $vmss.properties.virtualMachineProfile
        $profile.osProfile.computerNamePrefix = $NodeTypeName
        $profile.osProfile.adminUsername = 'vmadmin'
        $profile.osProfile.secrets[0].sourceVault.id = "$resourcePrefix/Microsoft.KeyVault/vaults/FT-KV4ServiceFabric-PRD"
        $profile.osProfile.secrets[0].vaultCertificates[0].certificateUrl = 'https://test-vault.vault.azure.net/secrets/cluster-cert/test-version'
        $profile.storageProfile.imageReference.publisher = 'MicrosoftWindowsServer'
        $profile.storageProfile.imageReference.offer = 'WindowsServer'
        $profile.storageProfile.imageReference.sku = $ImageSku
        $profile.storageProfile.imageReference.version = 'latest'
        $profile.storageProfile.osDisk.managedDisk.storageAccountType = 'Standard_LRS'
        $profile.storageProfile.osDisk | Add-Member -NotePropertyName diskSizeGB -NotePropertyValue 128 -Force
        $profile.storageProfile | Add-Member -NotePropertyName dataDisks -NotePropertyValue @() -Force

        $nic = $profile.networkProfile.networkInterfaceConfigurations[0]
        $nic.properties | Add-Member -NotePropertyName enableAcceleratedNetworking -NotePropertyValue $true -Force
        $ipConfig = $nic.properties.ipConfigurations[0]
        $ipConfig.properties.subnet.id = "$resourcePrefix/Microsoft.Network/virtualNetworks/PA-ServiceFabric-VNet/subnets/PA-ServiceFabric-Subnet"
        $ipConfig.properties.loadBalancerBackendAddressPools[0].id = "$resourcePrefix/Microsoft.Network/loadBalancers/LB-$ClusterName-$NodeTypeName/backendAddressPools/LoadBalancerBEAddressPool"
        $ipConfig.properties.loadBalancerInboundNatPools[0].id = "$resourcePrefix/Microsoft.Network/loadBalancers/LB-$ClusterName-$NodeTypeName/inboundNatPools/LoadBalancerBEAddressNatPool"

        $extensions = @($profile.extensionProfile.extensions)
        $sfExtension = $extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
        $sfExtension.properties.settings.clusterEndpoint = "https://$ClusterName.$Location.servicefabric.azure.com"
        $sfExtension.properties.settings.nodeTypeRef = $NodeTypeName
        $sfExtension.properties.settings.durabilityLevel = $DurabilityLevel
        $sfExtension.properties.settings.certificate.thumbprint = $script:TestCertThumbprint
        $extensions += [pscustomobject]@{
            name = 'IaaSDiagnostics'
            properties = [pscustomobject]@{
                publisher = 'Microsoft.Azure.Diagnostics'
                type = 'IaaSDiagnostics'
                typeHandlerVersion = '1.5'
            }
        }
        $extensions += [pscustomobject]@{
            name = 'AzureMonitorWindowsAgent'
            properties = [pscustomobject]@{
                publisher = 'Microsoft.Azure.Monitor'
                type = 'AzureMonitorWindowsAgent'
                typeHandlerVersion = '1.0'
            }
        }
        $profile.extensionProfile.extensions = $extensions

        $cluster.name = $ClusterName
        $cluster.location = $Location
        $cluster.properties | Add-Member `
            -NotePropertyName clusterEndpoint `
            -NotePropertyValue "https://$ClusterName.$Location.servicefabric.azure.com" `
            -Force
        $cluster.properties.managementEndpoint = "https://$ClusterName.$Location.cloudapp.azure.com:19080"
        $cluster.properties.nodeTypes[0].name = $NodeTypeName
        $cluster.properties.nodeTypes[0].durabilityLevel = $DurabilityLevel
        $cluster.properties.nodeTypes[0].vmInstanceCount = $Capacity
        $cluster.properties.nodeTypes[0].clientConnectionEndpointPort = 19000
        $cluster.properties.nodeTypes[0].httpGatewayEndpointPort = 19080
        $cluster.properties.nodeTypes[0].applicationPorts.startPort = 20000
        $cluster.properties.nodeTypes[0].applicationPorts.endPort = 30000
        $cluster.properties.nodeTypes[0].ephemeralPorts.startPort = 49152
        $cluster.properties.nodeTypes[0].ephemeralPorts.endPort = 65534
        $cluster.properties.diagnosticsStorageAccountConfig.storageAccountName = "sflogs$($ClusterName.Replace('-', ''))"
        $cluster.tags.clusterName = $ClusterName

        $template.resources = @($vmss, $cluster)
        $template | ConvertTo-Json -Depth 50 | Set-Content -Path $Path -Encoding utf8
    }

    New-Item -ItemType Directory -Path $script:FixtureBase -Force | Out-Null
    New-TestExport `
        -Path $script:ProdExport `
        -ResourceGroupName 'demo-sf-rg' `
        -ClusterName 'demo-sf-cluster' `
        -NodeTypeName 'node0vm' `
        -Capacity 13 `
        -Location 'westeurope' `
        -ImageSku '2019-Datacenter' `
        -DurabilityLevel 'Silver'
    New-TestExport `
        -Path $script:DevExport `
        -ResourceGroupName 'demo-sf-dev' `
        -ClusterName 'demo-sf-dev' `
        -NodeTypeName 'devnt0' `
        -Capacity 5 `
        -Location 'eastus' `
        -ImageSku '2022-Datacenter' `
        -DurabilityLevel 'Silver'

    # Portal-style export: two node types, IDs expressed as [resourceId(parameters(...))]
    $script:MultiExport = Join-Path $script:FixtureBase 'sf-multi_rg_template.json'
    New-TestExport `
        -Path $script:MultiExport `
        -ResourceGroupName 'sf-multi' `
        -ClusterName 'sf-multi' `
        -NodeTypeName 'nt0' `
        -Capacity 5 `
        -Location 'westeurope' `
        -ImageSku '2016-Datacenter-Server-Core' `
        -DurabilityLevel 'Silver'
    $multi = Get-Content $script:MultiExport -Raw | ConvertFrom-Json
    $mVmss0 = $multi.resources | Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachineScaleSets' } | Select-Object -First 1
    $mCluster = $multi.resources | Where-Object { $_.type -eq 'Microsoft.ServiceFabric/clusters' } | Select-Object -First 1
    $mVmss1 = $mVmss0 | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $mVmss1.name = 'nt1'
    $mVmss1.properties.virtualMachineProfile.osProfile.computerNamePrefix = 'nt1'
    ($mVmss1.properties.virtualMachineProfile.extensionProfile.extensions |
        Where-Object { $_.properties.type -eq 'ServiceFabricNode' }).properties.settings.nodeTypeRef = 'nt1'
    foreach ($pair in @(@($mVmss0, 'nt0'), @($mVmss1, 'nt1'))) {
        $ipc = $pair[0].properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0]
        $ipc.properties.loadBalancerBackendAddressPools[0].id = "[resourceId('Microsoft.Network/loadBalancers/backendAddressPools', parameters('loadBalancers_lb_$($pair[1])_name'), 'LoadBalancerBEAddressPool')]"
        $ipc.properties.PSObject.Properties.Remove('loadBalancerInboundNatPools')
        $multi.parameters | Add-Member -NotePropertyName "loadBalancers_lb_$($pair[1])_name" -NotePropertyValue ([pscustomobject]@{ type = 'String'; defaultValue = "LB-sf-multi-$($pair[1])" }) -Force
    }
    $mVmss0.properties.virtualMachineProfile.storageProfile.imageReference | Add-Member -NotePropertyName exactVersion -NotePropertyValue '14393.0.0' -Force
    $nt1 = $mCluster.properties.nodeTypes[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $nt1.name = 'nt1'
    $nt1.isPrimary = $false
    $mCluster.properties.nodeTypes = @($mCluster.properties.nodeTypes[0], $nt1)
    $multi.resources = @($mVmss0, $mVmss1, $mCluster)
    $multi | ConvertTo-Json -Depth 50 | Set-Content -Path $script:MultiExport -Encoding utf8

    # Shared 'exec' package used by every execution-based validation-script test below.
    # Generated once here so those Contexts are independent of run order.
    $script:ExecOutput = Join-Path $script:OutputBase 'exec'
    $script:ValidationScript = Join-Path $script:ExecOutput 'Test-ScaleUpReadiness.ps1'
    if (Test-Path $script:ProdExport) {
        & $script:ScriptPath `
            -TemplateExportPath $script:ProdExport `
            -TargetVmSku 'Standard_D8ads_v5' `
            -ReplacementVmssName 'nt0new' `
            -OutputPath $script:ExecOutput | Out-Null
    }

    # Pester can only mock an existing command. Provide stubs for any Az / SF cmdlet
    # missing on the test host so the generated script's external calls are fully
    # neutralised (no real Azure or Service Fabric connection is attempted).
    foreach ($cmd in 'Get-AzVmss', 'Get-AzContext', 'Get-AzServiceFabricCluster',
        'Get-AzResourceGroup', 'Get-AzVMUsage', 'Connect-ServiceFabricCluster',
        'Get-ServiceFabricNode', 'Get-ServiceFabricClusterHealth') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Set-Item "function:global:$cmd" { param($ResourceGroupName, $VMScaleSetName, $Location, $Name) }
        }
    }
}

AfterAll {
    if (Test-Path $script:OutputBase) {
        Remove-Item $script:OutputBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'New-ServiceFabricScaleUpPackage' {

    Context 'Prerequisites' {
        It 'Script parses without errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It 'Does not use ConvertFrom-Json -Depth (unsupported on Windows PowerShell 5.1)' {
            # ConvertFrom-Json gained -Depth in PowerShell 6. On 5.1 it throws
            # "A parameter cannot be found that matches parameter name 'Depth'" at runtime,
            # which AST parsing cannot detect. Guard statically instead.
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Not -Match 'ConvertFrom-Json\s+(-\w+\s+\S+\s+)*-Depth'
        }

        It 'Production fixture exists' {
            $script:ProdExport | Should -Exist
        }

        It 'Dev fixture exists' {
            $script:DevExport | Should -Exist
        }
    }

    Context 'Generated validation script robustness (fixture-independent)' {
        # Guard against placeholder values from export-mode discovery
        # ('<resource-group-from-export>') being passed unguarded to Az cmdlets,
        # which trips Az [ValidatePattern] and produces a cryptic runtime error.
        BeforeAll {
            $script:SourceContent = Get-Content $script:ScriptPath -Raw
        }

        It 'PreFlight validates ResourceGroupName before calling Az cmdlets' {
            $script:SourceContent | Should -Match '\$rgValid\s*=\s*`?\$ResourceGroupName\s+-match'
        }

        It 'PreFlight guards the quota check behind a valid resource-group test' {
            # Get-AzResourceGroup must only run when the RG name is valid.
            $script:SourceContent | Should -Match 'if\s*\(`?\$rgValid\)\s*\{[\s\S]*?Get-AzResourceGroup'
        }

        It 'PreFlight skips cluster checks for placeholder resource groups' {
            $script:SourceContent | Should -Match '\[SKIP\] Cluster checks'
        }

        It 'Generated SF connect blocks guard against placeholder ManagementEndpoint' {
            # Export mode cannot always discover the management endpoint. The drain,
            # cleanup, and validation scripts must refuse a '<...>' placeholder rather
            # than passing it to Connect-ServiceFabricCluster (cryptic connect failure).
            $guardCount = ([regex]::Matches($script:SourceContent, "ManagementEndpoint -match '\^<\.\*>")).Count
            $guardCount | Should -BeGreaterOrEqual 3
        }

        It 'Resolves ManagementEndpoint from the export cluster resource' {
            $script:SourceContent | Should -Match '\$managementEndpoint\s*=\s*resolve-exportValue\s+\$clusterResource\.properties\.managementEndpoint'
        }

        It 'Derives ResourceGroupName from the export file name and cross-validates it' {
            # An ARM export does not store its own source resource-group name, but the
            # portal '<rg>_rg_template.json' naming does. Resolution must derive from the
            # file name and only trust it when a matching '/resourceGroups/<name>/' ID exists.
            $script:SourceContent | Should -Match '\[System\.IO\.Path\]::GetFileName\(\$exportPath\)'
            $script:SourceContent | Should -Match ([regex]::Escape('/resourceGroups/$rgCandidate/'))
        }
    }

    Context 'WhatIf support' {
        It 'Has SupportsShouldProcess declared' {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
        }

        It '-WhatIf produces no output files' {
            $whatifDir = Join-Path $script:OutputBase 'whatif-test'
            & $script:ScriptPath `
                -TemplateExportPath $script:ProdExport `
                -TargetVmSku 'Standard_D4s_v5' `
                -ReplacementVmssName 'wif' `
                -OutputPath $whatifDir `
                -WhatIf 2>&1 | Out-Null

            $whatifDir | Should -Not -Exist
        }
    }

    Context 'Export mode - production fixture (13-node demo-sf-cluster)' {
        BeforeAll {
            $script:ProdOutput = Join-Path $script:OutputBase 'prod'
            & $script:ScriptPath `
                -TemplateExportPath $script:ProdExport `
                -TargetVmSku 'Standard_D4s_v5' `
                -ReplacementVmssName 'ntnew' `
                -OutputPath $script:ProdOutput

            $script:Template = Get-Content (Join-Path $script:ProdOutput 'replacement-vmss.template.json') -Raw | ConvertFrom-Json
            $script:Params = Get-Content (Join-Path $script:ProdOutput 'replacement-vmss.parameters.json') -Raw | ConvertFrom-Json
            $script:Resource = $script:Template.resources[0]
            $script:ResourceJson = $script:Resource | ConvertTo-Json -Depth 30
        }

        It 'Resolves ResourceGroupName from the export file name (demo-sf-rg)' {
            $validation = Get-Content (Join-Path $script:ProdOutput 'Test-ScaleUpReadiness.ps1') -Raw
            $validation | Should -Match "\`$ResourceGroupName = 'demo-sf-rg'"
            $validation | Should -Not -Match '<resource-group-from-export>'
        }

        It 'Generates all 6 expected files' {
            $files = Get-ChildItem $script:ProdOutput | Select-Object -ExpandProperty Name | Sort-Object
            $expected = @(
                'Invoke-DrainOldNodes.ps1',
                'Remove-StaleNodeState.ps1',
                'replacement-vmss.parameters.json',
                'replacement-vmss.template.json',
                'RUNBOOK.md',
                'Test-ScaleUpReadiness.ps1'
            ) | Sort-Object
            $files | Should -Be $expected
        }

        Describe 'Template structure' {
            It 'Uses correct ARM schema' {
                $script:Template.'$schema' | Should -Be 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
            }

            It 'Has exactly 4 parameters' {
                ($script:Template.parameters.PSObject.Properties | Measure-Object).Count | Should -Be 4
            }

            It 'Has replacementVmssName parameter (string, maxLength 9)' {
                $p = $script:Template.parameters.replacementVmssName
                $p.type | Should -Be 'string'
                $p.maxLength | Should -Be 9
            }

            It 'Has replacementVmssSize parameter with correct default' {
                $p = $script:Template.parameters.replacementVmssSize
                $p.type | Should -Be 'string'
                $p.defaultValue | Should -Be 'Standard_D4s_v5'
            }

            It 'Has replacementVmssInstanceCount parameter with minValue 5' {
                $p = $script:Template.parameters.replacementVmssInstanceCount
                $p.type | Should -Be 'int'
                $p.minValue | Should -Be 5
                $p.defaultValue | Should -Be 13  # matches source capacity
            }

            It 'Has adminPassword parameter (securestring)' {
                $script:Template.parameters.adminPassword.type | Should -Be 'securestring'
            }

            It 'Has exactly 1 resource' {
                $script:Template.resources.Count | Should -Be 1
            }

            It 'Resource is a VMSS' {
                $script:Resource.type | Should -Be 'Microsoft.Compute/virtualMachineScaleSets'
            }

            It 'Resource name uses parameter reference' {
                $script:Resource.name | Should -Be "[parameters('replacementVmssName')]"
            }

            It 'SKU name uses parameter reference' {
                $script:Resource.sku.name | Should -Be "[parameters('replacementVmssSize')]"
            }

            It 'SKU capacity uses parameter reference' {
                $script:Resource.sku.capacity | Should -Be "[parameters('replacementVmssInstanceCount')]"
            }

            It 'computerNamePrefix uses parameter reference' {
                $script:Resource.properties.virtualMachineProfile.osProfile.computerNamePrefix | Should -Be "[parameters('replacementVmssName')]"
            }

            It 'adminPassword uses parameter reference' {
                $script:Resource.properties.virtualMachineProfile.osProfile.adminPassword | Should -Be "[parameters('adminPassword')]"
            }
        }

        Describe 'Read-only field stripping' {
            It 'No provisioningState anywhere in template' {
                $script:ResourceJson | Should -Not -Match '"provisioningState"'
            }

            It 'No etag on resource' {
                $script:Resource.PSObject.Properties['etag'] | Should -BeNullOrEmpty
            }

            It 'No timeCreated anywhere in template' {
                $script:ResourceJson | Should -Not -Match '"timeCreated"'
            }

            It 'No uniqueId anywhere in template' {
                $script:ResourceJson | Should -Not -Match '"uniqueId"'
            }
        }

        Describe 'Preserved VMSS properties' {
            It 'Preserves location' {
                $script:Resource.location | Should -Be 'westeurope'
            }

            It 'Preserves singlePlacementGroup' {
                $script:Resource.properties.singlePlacementGroup | Should -Be $true
            }

            It 'Preserves platformFaultDomainCount' {
                $script:Resource.properties.platformFaultDomainCount | Should -Be 5
            }

            It 'Preserves overprovision as false' {
                $script:Resource.properties.overprovision | Should -Be $false
            }

            It 'Preserves upgradePolicy mode' {
                $script:Resource.properties.upgradePolicy.mode | Should -Be 'Automatic'
            }

            It 'Preserves OS image reference' {
                $img = $script:Resource.properties.virtualMachineProfile.storageProfile.imageReference
                $img.publisher | Should -Be 'MicrosoftWindowsServer'
                $img.offer | Should -Be 'WindowsServer'
                $img.sku | Should -Be '2019-Datacenter'
            }

            It 'Preserves managedDisk storageAccountType' {
                $script:Resource.properties.virtualMachineProfile.storageProfile.osDisk.managedDisk.storageAccountType | Should -Be 'Standard_LRS'
            }

            It 'Preserves subnet reference' {
                $subnet = $script:Resource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id
                $subnet | Should -Match 'PA-ServiceFabric-Subnet'
            }

            It 'Preserves load balancer backend pool reference' {
                $lbPools = $script:Resource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.loadBalancerBackendAddressPools
                $lbPools.Count | Should -BeGreaterOrEqual 1
                $lbPools[0].id | Should -Match 'LB-demo-sf-cluster-node0vm'
            }

            It 'Preserves KeyVault secrets' {
                $secrets = $script:Resource.properties.virtualMachineProfile.osProfile.secrets
                $secrets.Count | Should -BeGreaterOrEqual 1
                $secrets[0].sourceVault.id | Should -Match 'FT-KV4ServiceFabric-PRD'
            }

            It 'Preserves identity type' {
                $script:Resource.identity.type | Should -Be 'SystemAssigned'
            }

            It 'Preserves tags' {
                $script:Resource.tags.clusterName | Should -Be 'demo-sf-cluster'
            }
        }

        Describe 'Extension filtering' {
            BeforeAll {
                $script:Extensions = $script:Resource.properties.virtualMachineProfile.extensionProfile.extensions
            }

            It 'Excludes IaaSDiagnostics (retired)' {
                $script:Extensions | Where-Object { $_.properties.type -eq 'IaaSDiagnostics' } | Should -BeNullOrEmpty
            }

            It 'Includes ServiceFabricNode extension' {
                $sfExt = $script:Extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
                $sfExt | Should -Not -BeNullOrEmpty
            }

            It 'SF extension has protectedSettings with listKeys' {
                $sfExt = $script:Extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
                $sfExt.properties.protectedSettings.StorageAccountKey1 | Should -Match 'listKeys'
                $sfExt.properties.protectedSettings.StorageAccountKey2 | Should -Match 'listKeys'
            }

            It 'SF extension has correct cluster endpoint' {
                $sfExt = $script:Extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
                $sfExt.properties.settings.clusterEndpoint | Should -Match 'westeurope.servicefabric.azure.com'
            }

            It 'SF extension has correct node type ref' {
                $sfExt = $script:Extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
                $sfExt.properties.settings.nodeTypeRef | Should -Be 'node0vm'
            }

            It 'SF extension has correct durability level' {
                $sfExt = $script:Extensions | Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
                $sfExt.properties.settings.durabilityLevel | Should -Be 'Silver'
            }

            It 'Includes AzureMonitorWindowsAgent extension' {
                $monExt = $script:Extensions | Where-Object { $_.properties.type -eq 'AzureMonitorWindowsAgent' }
                $monExt | Should -Not -BeNullOrEmpty
            }
        }

        Describe 'Parameter file' {
            It 'Uses correct schema' {
                $script:Params.'$schema' | Should -Be 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            }

            It 'Has exactly 4 parameter values' {
                ($script:Params.parameters.PSObject.Properties | Measure-Object).Count | Should -Be 4
            }

            It 'replacementVmssName is ntnew' {
                $script:Params.parameters.replacementVmssName.value | Should -Be 'ntnew'
            }

            It 'replacementVmssSize matches target SKU' {
                $script:Params.parameters.replacementVmssSize.value | Should -Be 'Standard_D4s_v5'
            }

            It 'replacementVmssInstanceCount matches source capacity' {
                $script:Params.parameters.replacementVmssInstanceCount.value | Should -Be 13
            }

            It 'adminPassword is a placeholder' {
                $script:Params.parameters.adminPassword.value | Should -Match '<REQUIRED'
            }
        }

        Describe 'Drain script' {
            BeforeAll {
                $script:DrainContent = Get-Content (Join-Path $script:ProdOutput 'Invoke-DrainOldNodes.ps1') -Raw
            }

            It 'Contains seed node ordering comment or logic' {
                $script:DrainContent | Should -Match 'seed|Seed'
            }

            It 'Contains the original node type name' {
                $script:DrainContent | Should -Match 'node0vm'
            }

            It 'Is valid PowerShell' {
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($script:DrainContent, [ref]$null, [ref]$errors)
                $errors.Count | Should -Be 0
            }
        }

        Describe 'Cleanup script' {
            BeforeAll {
                $script:CleanupContent = Get-Content (Join-Path $script:ProdOutput 'Remove-StaleNodeState.ps1') -Raw
            }

            It 'Contains Remove-ServiceFabricNodeState reference' {
                $script:CleanupContent | Should -Match 'Remove-ServiceFabricNodeState'
            }

            It 'Is valid PowerShell' {
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($script:CleanupContent, [ref]$null, [ref]$errors)
                $errors.Count | Should -Be 0
            }
        }

        Describe 'Validation script' {
            BeforeAll {
                $script:ValidationContent = Get-Content (Join-Path $script:ProdOutput 'Test-ScaleUpReadiness.ps1') -Raw
            }

            It 'Contains pre-flight checks' {
                $script:ValidationContent | Should -Match 'pre-?flight|PreFlight|preflight'
            }

            It 'Guards Az resource-group calls against invalid/placeholder RG names' {
                # Regression: export-mode injects '<resource-group-from-export>' which
                # violates Az [ValidatePattern]. The generated PreFlight must validate
                # the RG name before invoking Get-AzResourceGroup / Get-AzServiceFabricCluster.
                $script:ValidationContent | Should -Match '\$rgValid\s*=\s*\$ResourceGroupName\s+-match'
                $script:ValidationContent | Should -Match '\[SKIP\] Quota check'
            }

            It 'Is valid PowerShell' {
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($script:ValidationContent, [ref]$null, [ref]$errors)
                $errors.Count | Should -Be 0
            }
        }

        Describe 'Runbook' {
            BeforeAll {
                $script:RunbookContent = Get-Content (Join-Path $script:ProdOutput 'RUNBOOK.md') -Raw
            }

            It 'Is markdown with headings' {
                $script:RunbookContent | Should -Match '^#'
            }

            It 'References the cluster name' {
                $script:RunbookContent | Should -Match 'demo-sf-cluster'
            }

            It 'References the target SKU' {
                $script:RunbookContent | Should -Match 'Standard_D4s_v5'
            }

            It 'Documents rollback by reactivating preserved old nodes' {
                $script:RunbookContent | Should -Match 'Roll Back Before Old VMSS Deletion'
                $script:RunbookContent | Should -Match 'Enable-ServiceFabricNode -NodeName'
                $script:RunbookContent | Should -Match 'does not normally stop, restart, or reimage the VM'
            }

            It 'Reverse-drains replacement nodes one at a time with seeds last' {
                $script:RunbookContent | Should -Match "NodeName -like '_ntnew_\*'"
                $script:RunbookContent | Should -Match 'Sort-Object IsSeedNode'
                $script:RunbookContent | Should -Match 'Disable-ServiceFabricNode -NodeName \$node.NodeName -Intent RemoveNode'
                $script:RunbookContent | Should -Match "NodeStatus -eq 'Disabled'[\s\S]*DeactivationInfo.Status -eq 'Completed'"
            }

            It 'Defines deletion and node-state cleanup as the recovery boundary' {
                $script:RunbookContent | Should -Match 'Recovery boundary:.*old VMSS is deleted'
                $script:RunbookContent | Should -Match 'fresh capacity\s+deployment rather than simple node reactivation'
            }
        }
    }

    Context 'Export mode - dev fixture (different topology)' {
        BeforeAll {
            $script:DevOutput = Join-Path $script:OutputBase 'dev'
            & $script:ScriptPath `
                -TemplateExportPath $script:DevExport `
                -TargetVmSku 'Standard_D2s_v5' `
                -ReplacementVmssName 'devnew' `
                -OutputPath $script:DevOutput

            $script:DevTemplate = Get-Content (Join-Path $script:DevOutput 'replacement-vmss.template.json') -Raw | ConvertFrom-Json
            $script:DevResource = $script:DevTemplate.resources[0]
        }

        It 'Generates 6 files' {
            (Get-ChildItem $script:DevOutput | Measure-Object).Count | Should -Be 6
        }

        It 'Discovers a different node type than production' {
            $devNodeType = ($script:DevResource.properties.virtualMachineProfile.extensionProfile.extensions |
                Where-Object { $_.properties.type -eq 'ServiceFabricNode' }).properties.settings.nodeTypeRef
            $devNodeType | Should -Not -Be 'node0vm'
        }

        It 'Uses the correct target SKU' {
            $script:DevTemplate.parameters.replacementVmssSize.defaultValue | Should -Be 'Standard_D2s_v5'
        }

        It 'Template has no read-only fields' {
            $json = $script:DevResource | ConvertTo-Json -Depth 30
            $json | Should -Not -Match '"provisioningState"'
            $json | Should -Not -Match '"timeCreated"'
            $json | Should -Not -Match '"etag"'
        }
    }

    Context 'SkipDrainScripts switch' {
        BeforeAll {
            $script:SkipOutput = Join-Path $script:OutputBase 'skip-drain'
            & $script:ScriptPath `
                -TemplateExportPath $script:ProdExport `
                -TargetVmSku 'Standard_D4s_v5' `
                -ReplacementVmssName 'skp' `
                -OutputPath $script:SkipOutput `
                -SkipDrainScripts
        }

        It 'Generates only 3 files (template, params, runbook)' {
            $files = Get-ChildItem $script:SkipOutput | Select-Object -ExpandProperty Name | Sort-Object
            $expected = @('replacement-vmss.parameters.json', 'replacement-vmss.template.json', 'RUNBOOK.md') | Sort-Object
            $files | Should -Be $expected
        }
    }

    Context 'InstanceCount override' {
        BeforeAll {
            $script:OverrideOutput = Join-Path $script:OutputBase 'override'
            & $script:ScriptPath `
                -TemplateExportPath $script:ProdExport `
                -TargetVmSku 'Standard_D4s_v5' `
                -ReplacementVmssName 'ovr' `
                -OutputPath $script:OverrideOutput `
                -InstanceCount 7 `
                -SkipDrainScripts

            $script:OverrideTemplate = Get-Content (Join-Path $script:OverrideOutput 'replacement-vmss.template.json') -Raw | ConvertFrom-Json
            $script:OverrideParams = Get-Content (Join-Path $script:OverrideOutput 'replacement-vmss.parameters.json') -Raw | ConvertFrom-Json
        }

        It 'Template defaultValue reflects override' {
            $script:OverrideTemplate.parameters.replacementVmssInstanceCount.defaultValue | Should -Be 7
        }

        It 'Parameter file reflects override' {
            $script:OverrideParams.parameters.replacementVmssInstanceCount.value | Should -Be 7
        }
    }

    Context 'ARM expression resolver (export mode)' {
        BeforeAll {
            $script:ResolverOutput = Join-Path $script:OutputBase 'resolver'
            & $script:ScriptPath `
                -TemplateExportPath $script:ProdExport `
                -TargetVmSku 'Standard_D4s_v5' `
                -ReplacementVmssName 'res' `
                -OutputPath $script:ResolverOutput `
                -SkipDrainScripts

            $script:ResolverTemplate = Get-Content (Join-Path $script:ResolverOutput 'replacement-vmss.template.json') -Raw | ConvertFrom-Json
            $script:ResolverResource = $script:ResolverTemplate.resources[0]
        }

        It 'Resolves subnet ID (no [parameters()] or [concat()] expressions remain)' {
            $subnetId = $script:ResolverResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id
            $subnetId | Should -Not -Match '^\['
            $subnetId | Should -Match '/subnets/'
        }

        It 'Resolves load balancer backend pool ID' {
            $lbPool = $script:ResolverResource.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.loadBalancerBackendAddressPools[0].id
            $lbPool | Should -Not -Match '^\[concat'
            $lbPool | Should -Match 'loadBalancers'
            $lbPool | Should -Match '^(/subscriptions/|\[resourceId\()'
        }

        It 'Resolves KeyVault source vault ID' {
            $kvId = $script:ResolverResource.properties.virtualMachineProfile.osProfile.secrets[0].sourceVault.id
            $kvId | Should -Not -Match '^\['
            $kvId | Should -Match 'Microsoft.KeyVault/vaults'
        }

        It 'Preserves listKeys expressions (runtime ARM functions)' {
            $sfExt = $script:ResolverResource.properties.virtualMachineProfile.extensionProfile.extensions |
                Where-Object { $_.properties.type -eq 'ServiceFabricNode' }
            $sfExt.properties.protectedSettings.StorageAccountKey1 | Should -Match '^\[listKeys'
        }
    }

    Context 'Portal-style export: resourceId() IDs, -NodeTypeName, -TargetImageSku' {
        BeforeAll {
            $script:MultiPrimaryOut = Join-Path $script:OutputBase 'multi-primary'
            & $script:ScriptPath `
                -TemplateExportPath $script:MultiExport `
                -TargetVmSku 'Standard_E4s_v3' `
                -ReplacementVmssName 'nt0new' `
                -OutputPath $script:MultiPrimaryOut `
                -TargetImageSku '2025-datacenter-core-g2' `
                -SkipDrainScripts *> $null
            $script:MultiPrimary = (Get-Content (Join-Path $script:MultiPrimaryOut 'replacement-vmss.template.json') -Raw | ConvertFrom-Json).resources[0]

            $script:MultiNt1Out = Join-Path $script:OutputBase 'multi-nt1'
            & $script:ScriptPath `
                -TemplateExportPath $script:MultiExport `
                -TargetVmSku 'Standard_E4s_v3' `
                -ReplacementVmssName 'nt1new' `
                -OutputPath $script:MultiNt1Out `
                -NodeTypeName 'nt1' `
                -SkipDrainScripts *> $null
            $script:MultiNt1 = (Get-Content (Join-Path $script:MultiNt1Out 'replacement-vmss.template.json') -Raw | ConvertFrom-Json).resources[0]
            $script:MultiNt1Runbook = Get-Content (Join-Path $script:MultiNt1Out 'RUNBOOK.md') -Raw
        }

        It 'Emits the LB backend pool as a deployable resourceId() expression, not a /providers/ path' {
            $id = $script:MultiPrimary.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.loadBalancerBackendAddressPools[0].id
            $id | Should -Be "[resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'LB-sf-multi-nt0', 'LoadBalancerBEAddressPool')]"
            $id | Should -Not -Match '^/providers/'
            $id | Should -Not -Match 'parameters\('
        }

        It 'Defaults to the primary node type VMSS' {
            ($script:MultiPrimary.properties.virtualMachineProfile.extensionProfile.extensions |
                Where-Object { $_.properties.type -eq 'ServiceFabricNode' }).properties.settings.nodeTypeRef | Should -Be 'nt0'
        }

        It '-TargetImageSku replaces the image SKU and drops the pinned exactVersion' {
            $img = $script:MultiPrimary.properties.virtualMachineProfile.storageProfile.imageReference
            $img.sku | Should -Be '2025-datacenter-core-g2'
            $img.version | Should -Be 'latest'
            $img.PSObject.Properties['exactVersion'] | Should -BeNullOrEmpty
        }

        It 'Leaves the image unchanged when -TargetImageSku is omitted' {
            $script:MultiNt1.properties.virtualMachineProfile.storageProfile.imageReference.sku | Should -Be '2016-Datacenter-Server-Core'
        }

        It '-NodeTypeName clones the VMSS whose nodeTypeRef matches (non-primary)' {
            ($script:MultiNt1.properties.virtualMachineProfile.extensionProfile.extensions |
                Where-Object { $_.properties.type -eq 'ServiceFabricNode' }).properties.settings.nodeTypeRef | Should -Be 'nt1'
            $script:MultiNt1.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.loadBalancerBackendAddressPools[0].id |
                Should -Match "'LB-sf-multi-nt1'"
        }

        It 'Runbook reports the selected node type as non-primary' {
            $script:MultiNt1Runbook | Should -Match '\| Node type \| `nt1` \(primary: False\) \|'
        }

        It '-NodeTypeName that does not exist produces no package' {
            $out = Join-Path $script:OutputBase 'multi-missing'
            & $script:ScriptPath -TemplateExportPath $script:MultiExport -TargetVmSku 'Standard_E4s_v3' `
                -ReplacementVmssName 'bad' -OutputPath $out -NodeTypeName 'nope' -SkipDrainScripts *> $null
            Test-Path (Join-Path $out 'replacement-vmss.template.json') | Should -BeFalse
        }

        It '-SeparateNodeType fails fast instead of silently generating a same-node-type package' {
            $out = Join-Path $script:OutputBase 'multi-separate'
            & $script:ScriptPath -TemplateExportPath $script:MultiExport -TargetVmSku 'Standard_E4s_v3' `
                -ReplacementVmssName 'sep' -OutputPath $out -SeparateNodeType -SkipDrainScripts *> $null
            Test-Path (Join-Path $out 'replacement-vmss.template.json') | Should -BeFalse
        }
    }

    Context 'Generated validation script - PostDeploy behavior (execution with mocks)' {
        # Regression coverage for the field failures where PostDeploy reported a
        # misleading "VMSS not found" (Get-AzVmss -ErrorAction SilentlyContinue masking
        # the real error) and crashed with "Get-ServiceFabricNode is not recognized"
        # when the Service Fabric SDK was absent. These tests EXECUTE the generated
        # script with mocks instead of only matching its source text.
        BeforeAll {
            # The shared 'exec' package and command stubs are created in the top-level
            # BeforeAll. Here we only define the PostDeploy invocation helper. SF cmdlets
            # are mocked to no-ops so the run is deterministic on any host. *>&1 captures
            # the Write-Host output the generated script uses for its PASS/FAIL lines.
            function script:Invoke-PostDeploy([scriptblock]$VmssMock) {
                Mock Get-AzVmss $VmssMock
                Mock Connect-ServiceFabricCluster {}
                Mock Get-ServiceFabricNode { @() }
                Mock Get-ServiceFabricClusterHealth { [pscustomobject]@{ AggregatedHealthState = 'Ok' } }
                & $script:ValidationScript `
                    -Phase PostDeploy `
                    -ResourceGroupName 'ztestSFRG' `
                    -ReplacementVmssName 'nt0new' `
                    -TargetVmSku 'Standard_D8ads_v5' `
                    -ManagementEndpoint 'https://ztest.eastus.cloudapp.azure.com:19080' `
                    -CertThumbprint $script:TestCertThumbprint *>&1 | Out-String
            }
        }

        It 'PASSes when Get-AzVmss returns the deployed VMSS' {
            $out = Invoke-PostDeploy {
                [pscustomobject]@{
                    ProvisioningState = 'Succeeded'
                    Sku               = [pscustomobject]@{ Name = 'Standard_D8ads_v5' }
                }
            }
            $out | Should -Match '\[PASS\] Replacement VMSS exists'
            $out | Should -Match 'VMSS provisioning succeeded'
        }

        It 'Completes without an unhandled "not recognized" error' {
            # The original bug aborted PostDeploy with "Get-ServiceFabricNode is not
            # recognized" under $ErrorActionPreference=Stop. The run must now finish and
            # print its results footer regardless of SF node-state handling.
            $out = Invoke-PostDeploy {
                [pscustomobject]@{
                    ProvisioningState = 'Succeeded'
                    Sku               = [pscustomobject]@{ Name = 'Standard_D8ads_v5' }
                }
            }
            $out | Should -Not -Match 'is not recognized as a name of a cmdlet'
            $out | Should -Match '--- Results:'
        }

        It 'Reports an actionable not-found message (with RG and Get-AzContext hint) on a not-found error' {
            $out = Invoke-PostDeploy { throw 'The Resource ''Microsoft.Compute/virtualMachineScaleSets/nt0new'' under resource group ''ztestSFRG'' was not found.' }
            $out | Should -Match "not found in RG 'ztestSFRG'"
            $out | Should -Match 'Get-AzContext'
            $out | Should -Not -Match 'is not recognized as a name of a cmdlet'
        }

        It 'Distinguishes a lookup error (auth/throttle) from a genuine not-found' {
            $out = Invoke-PostDeploy { throw 'AuthenticationFailed: the access token has expired.' }
            $out | Should -Match 'Get-AzVmss failed'
            $out | Should -Match 'AuthenticationFailed'
            $out | Should -Not -Match "not found in RG 'ztestSFRG'"
        }
    }

    Context 'Generated validation script - degradation guards (static)' {
        BeforeAll {
            $script:ExecValidation = Get-Content (Join-Path $script:OutputBase 'exec\Test-ScaleUpReadiness.ps1') -Raw
        }

        It 'Tracks SF module availability instead of assuming the cmdlets exist' {
            $script:ExecValidation | Should -Match '\$sfAvailable\s*=\s*\$null\s+-ne\s+\(Get-Command\s+''Get-ServiceFabricNode'''
        }

        It 'Falls back to importing the ServiceFabric module by name' {
            $script:ExecValidation | Should -Match 'Import-Module ServiceFabric -ErrorAction SilentlyContinue'
        }

        It 'Guards every SF node-state call behind $sfAvailable' {
            # No SF cmdlet should be invoked outside an "if (... $sfAvailable ...)" guard.
            # Expected guards: WARN banner, connect block, PostDeploy, PostDrain, PostCleanup.
            ([regex]::Matches($script:ExecValidation, 'if\s*\([^)]*\$sfAvailable')).Count |
                Should -BeGreaterOrEqual 4
        }

        It 'Uses -ErrorAction Stop (not SilentlyContinue) for the PostDeploy VMSS lookup' {
            $script:ExecValidation | Should -Match 'Get-AzVmss[^\r\n]*-ErrorAction Stop'
            $script:ExecValidation | Should -Not -Match 'Get-AzVmss[^\r\n]*-ErrorAction SilentlyContinue'
        }

        It 'Derives PostDrain/PostCleanup node-count thresholds from $ExpectedNodeCount (not a hardcoded 5)' {
            # Regression: the live e2e on a 3-node cluster false-failed because the checks
            # hardcoded '-ge 5'. They must compare against the baked $ExpectedNodeCount.
            $script:ExecValidation | Should -Match '\$upNodes\.Count -ge \$ExpectedNodeCount'
            $script:ExecValidation | Should -Match '\$allUp\.Count -ge \$ExpectedNodeCount'
            $script:ExecValidation | Should -Not -Match '\.Count -ge 5\b'
        }

        It 'Bakes the $ExpectedNodeCount default from the discovered capacity (13 for the prod fixture)' {
            $script:ExecValidation | Should -Match '\[int\]\$ExpectedNodeCount = 13'
        }
    }

    Context 'Generated validation script - PreFlight behavior (execution with mocks)' {
        It 'PASSes Azure login, cluster, and quota checks for a healthy cluster' {
            Mock Get-AzContext { [pscustomobject]@{ Account = 'tester' } }
            Mock Get-AzServiceFabricCluster { [pscustomobject]@{ ClusterState = 'Ready'; ProvisioningState = 'Succeeded' } }
            Mock Get-AzResourceGroup { [pscustomobject]@{ Location = 'eastus' } }
            Mock Get-AzVMUsage { [pscustomobject]@{ Name = [pscustomobject]@{ Value = 'cores' }; Limit = 100; CurrentValue = 10 } }

            $out = & $script:ValidationScript `
                -Phase PreFlight `
                -ResourceGroupName 'ztestSFRG' `
                -ClusterName 'ztestSFRG' *>&1 | Out-String

            $out | Should -Match '\[PASS\] Azure login'
            $out | Should -Match '\[PASS\] Cluster exists'
            $out | Should -Match '\[PASS\] Cluster state Ready'
            $out | Should -Match 'VM core quota'
            $out | Should -Match '--- Results:'
        }

        It 'FAILs the Azure-login check when no context is present' {
            Mock Get-AzContext { $null }
            Mock Get-AzServiceFabricCluster { [pscustomobject]@{ ClusterState = 'Ready'; ProvisioningState = 'Succeeded' } }
            Mock Get-AzResourceGroup { [pscustomobject]@{ Location = 'eastus' } }
            Mock Get-AzVMUsage { [pscustomobject]@{ Name = [pscustomobject]@{ Value = 'cores' }; Limit = 100; CurrentValue = 10 } }

            $out = & $script:ValidationScript `
                -Phase PreFlight `
                -ResourceGroupName 'ztestSFRG' `
                -ClusterName 'ztestSFRG' *>&1 | Out-String

            $out | Should -Match '\[FAIL\] Azure login'
        }
    }

    Context 'Generated validation script - PostDrain behavior (execution with mocks)' {
        It 'PASSes node, seed, and health checks after a successful drain' {
            $nodes = 1..5 | ForEach-Object {
                [pscustomobject]@{ NodeName = "_nt0new_$_"; NodeType = 'nt0new'; NodeStatus = 'Up'; IsSeedNode = ($_ -le 3) }
            }
            Mock Connect-ServiceFabricCluster {}
            Mock Get-ServiceFabricNode { $nodes }
            Mock Get-ServiceFabricClusterHealth { [pscustomobject]@{ AggregatedHealthState = 'Ok' } }

            $out = & $script:ValidationScript `
                -Phase PostDrain `
                -ExpectedNodeCount 5 `
                -ManagementEndpoint 'https://ztest.eastus.cloudapp.azure.com:19080' `
                -CertThumbprint $script:TestCertThumbprint *>&1 | Out-String

            $out | Should -Match '\[PASS\] Replacement nodes are Up'
            $out | Should -Match '\[PASS\] Seeds on replacement VMSS'
            $out | Should -Match '\[PASS\] Cluster health Ok'
        }

        It 'FAILs when too few seed nodes are active on the replacement VMSS' {
            $nodes = 1..5 | ForEach-Object {
                [pscustomobject]@{ NodeName = "_nt0new_$_"; NodeType = 'nt0new'; NodeStatus = 'Up'; IsSeedNode = ($_ -le 1) }
            }
            Mock Connect-ServiceFabricCluster {}
            Mock Get-ServiceFabricNode { $nodes }
            Mock Get-ServiceFabricClusterHealth { [pscustomobject]@{ AggregatedHealthState = 'Ok' } }

            $out = & $script:ValidationScript `
                -Phase PostDrain `
                -ExpectedNodeCount 5 `
                -ManagementEndpoint 'https://ztest.eastus.cloudapp.azure.com:19080' `
                -CertThumbprint $script:TestCertThumbprint *>&1 | Out-String

            $out | Should -Match '\[FAIL\] Seeds on replacement VMSS'
        }
    }

    Context 'Generated validation script - PostCleanup behavior (execution with mocks)' {
        It 'PASSes when all remaining nodes are Up and health is Ok' {
            $nodes = 1..5 | ForEach-Object {
                [pscustomobject]@{ NodeName = "_nt0new_$_"; NodeType = 'nt0new'; NodeStatus = 'Up'; IsSeedNode = ($_ -le 3) }
            }
            Mock Connect-ServiceFabricCluster {}
            Mock Get-ServiceFabricNode { $nodes }
            Mock Get-ServiceFabricClusterHealth { [pscustomobject]@{ AggregatedHealthState = 'Ok' } }

            $out = & $script:ValidationScript `
                -Phase PostCleanup `
                -ExpectedNodeCount 5 `
                -ManagementEndpoint 'https://ztest.eastus.cloudapp.azure.com:19080' `
                -CertThumbprint $script:TestCertThumbprint *>&1 | Out-String

            $out | Should -Match '\[PASS\] All remaining nodes are Up'
            $out | Should -Match '\[PASS\] At least 5 healthy nodes'
            $out | Should -Match '\[PASS\] Cluster health Ok'
        }

        It 'FAILs when a node remains in a non-Up state' {
            $nodes = @(
                [pscustomobject]@{ NodeName = '_nt0new_0'; NodeType = 'nt0new'; NodeStatus = 'Up'; IsSeedNode = $true }
                [pscustomobject]@{ NodeName = '_nt0_2'; NodeType = 'nt0'; NodeStatus = 'Down'; IsSeedNode = $false }
            )
            Mock Connect-ServiceFabricCluster {}
            Mock Get-ServiceFabricNode { $nodes }
            Mock Get-ServiceFabricClusterHealth { [pscustomobject]@{ AggregatedHealthState = 'Warning' } }

            $out = & $script:ValidationScript `
                -Phase PostCleanup `
                -ExpectedNodeCount 5 `
                -ManagementEndpoint 'https://ztest.eastus.cloudapp.azure.com:19080' `
                -CertThumbprint $script:TestCertThumbprint *>&1 | Out-String

            $out | Should -Match '\[FAIL\] All remaining nodes are Up'
            $out | Should -Match '\[FAIL\] Cluster health Ok'
        }
    }
}
