<#
.SYNOPSIS
    Queries Azure Instance Metadata Service (IMDS) from a Service Fabric VMSS node.

.DESCRIPTION
    Tests Azure VM metadata endpoints for managed identity tokens and instance metadata
    from a Service Fabric scale set node. Queries identity, instance, and attested
    metadata via the IMDS REST API at 169.254.169.254. Logs results to a file.

.NOTES

    File Name  : Get-ServiceFabricMetadata.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Get-ServiceFabricMetadata.ps1

.EXAMPLE
    .\Get-ServiceFabricMetadata.ps1 -iterations 5 -sleepMilliseconds 2000

.LINK
    https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token
#>
<#
    Script to test azure metadata identity and instance from a configured vm scaleset
    Script runs on vm scaleset node

    to run with no arguments:
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/servicefabric/sf-metadata-rest.ps1" -UseBasicParsing|iex

    or use the following to save and pass arguments:
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/sf-metadata-rest.ps1" -outFile "$pwd/sf-metadata-rest.ps1";
    .\sf-metadata-rest.ps1


    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-azure-powershell
    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-powershell-windows-vmss

    # if needed, enable system / user managed identity on scaleset
    PS C:\Users\jagilber> Update-AzVmss -ResourceGroupName sfcluster -Name nt0 -IdentityType "SystemAssigned"


    ResourceGroupName                           : sfcluster
    Sku                                         :
    Name                                      : Standard_D2_v2
    Tier                                      : Standard
    Capacity                                  : 1
    UpgradePolicy                               :
    Mode                                      : Automatic
    VirtualMachineProfile                       :
    OsProfile                                 :
        ComputerNamePrefix                      : nt0
        AdminUsername                           : cloudadmin
        WindowsConfiguration                    :
        ProvisionVMAgent                      : True
        EnableAutomaticUpdates                : True
        Secrets[0]                              :
        SourceVault                           :
            Id                                  : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/certs-                                                                                  example/providers/Microsoft.KeyVault/vaults/sf-example-kv
        VaultCertificates[0]                  :
            CertificateUrl                      :
    https://sf-example-kv.vault.azure.net/secrets/sf-example-cert/xxxxxxxxxxxxxxxxxxxxxxxxxxxx
            CertificateStore                    : My
    StorageProfile                            :
        ImageReference                          :
        Publisher                             : MicrosoftWindowsServer
        Offer                                 : WindowsServer
        Sku                                   : 2016-Datacenter-with-containers
        Version                               : latest
        OsDisk                                  :
        Caching                               : ReadOnly
        CreateOption                          : FromImage
        DiskSizeGB                            : 127
        ManagedDisk                           :
            StorageAccountType                  : Standard_LRS
    NetworkProfile                            :
        NetworkInterfaceConfigurations[0]       :
        Name                                  : NIC-0
        Primary                               : True
        EnableAcceleratedNetworking           : False
        DnsSettings                           :
        IpConfigurations[0]                   :
            Name                                : NIC-0
            Subnet                              :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-exa                                                                                  mple-rg/providers/Microsoft.Network/virtualNetworks/VNet/subnets/Subnet-0
            PrivateIPAddressVersion             : IPv4
            LoadBalancerBackendAddressPools[0]  :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-exa                                                                                  mple-rg/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/backendAddressPools/LoadBalancerBEAddressPool                                                                                           LoadBalancerInboundNatPools[0]      :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-exa                                                                                  mple-rg/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/inboundNatPools/LoadBalancerBEAddressNatPool                                                                                          EnableIPForwarding                    : False
    ExtensionProfile                          :
        Extensions[0]                           :
        Name                                  : nt0_ServiceFabricNode
        Publisher                             : Microsoft.Azure.ServiceFabric
        Type                                  : ServiceFabricNode
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              : {"clusterEndpoint":"https://eastus.servicefabric.azure.com/runtime/cluste                                                                                  rs/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","nodeTypeRef":"nt0","dataPath":"D:\\\\SvcFab","durabilityLevel":"Bronze","enab                                                                                  leParallelJobs":true,"nicPrefixOverride":"10.0.0.0/24","certificate":{"thumbprint":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX                                                                                  XXXX","x509StoreName":"My"}}
        Extensions[1]                           :
        Name                                  : VMDiagnosticsVmExt_vmNodeType0Name
        Publisher                             : Microsoft.Azure.Diagnostics
        Type                                  : IaaSDiagnostics
        TypeHandlerVersion                    : 1.5
        AutoUpgradeMinorVersion               : True
        Settings                              : {"WadCfg":{"DiagnosticMonitorConfiguration":{"overallQuotaInMB":"50000","                                                                                  EtwProviders":{"EtwEventSourceProviderConfiguration":[{"provider":"Microsoft-ServiceFabric-Actors","scheduledTransferKe                                                                                  ywordFilter":"1","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricReliableActorEventT                                                                                  able"}},{"provider":"Microsoft-ServiceFabric-Services","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestinat                                                                                  ion":"ServiceFabricReliableServiceEventTable"}}],"EtwManifestProviderConfiguration":[{"provider":"cbd93bc2-71e5-4566-b3                                                                                  a7-595d8eeca6e8","scheduledTransferLogLevelFilter":"Information","scheduledTransferKeywordFilter":"4611686018427387904"                                                                                  ,"scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricSystemEventTable"}}]}}},"StorageAcc                                                                                  ount":"examplestorageacct"}
        Extensions[2]                           :
        Name                                  : MMAExtension
        Publisher                             : Microsoft.EnterpriseCloud.Monitoring
        Type                                  : MicrosoftMonitoringAgent
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              :
    {"workspaceId":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","stopOnMultipleConnections":"true"}
    ProvisioningState                           : Succeeded
    Overprovision                               : False
    DoNotRunExtensionsOnOverprovisionedVMs      : False
    UniqueId                                    : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    SinglePlacementGroup                        : True
    Identity                                    :
    PrincipalId                               : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    TenantId                                  : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Type                                      : SystemAssigned
    Id                                          : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-exa
    mple-rg/providers/Microsoft.Compute/virtualMachineScaleSets/nt0
    Name                                        : nt0
    Type                                        : Microsoft.Compute/virtualMachineScaleSets
    Location                                    : eastus
    Tags                                        : {"resourceType":"Service Fabric","clusterName":"sfcluster"}


    # acquire system managed identity oauth token from within node
    (iwr -Method GET -Uri 'http://$ipAddress/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    PS C:\Users\cloudadmin> (iwr -Method GET -Uri 'http://$ipAddress/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    {
        "access_token":  "eyJ0eXAiOiJKV...",
        "client_id":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "expires_in":  "28799",
        "expires_on":  "1581563814",
        "ext_expires_in":  "28799",
        "not_before":  "1581534714",
        "resource":  "https://management.azure.com/",
        "token_type":  "Bearer"
    }

    # example instance rest query from within node
    (iwr -Method GET -Uri 'http://$ipAddress/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json

    PS C:\Users\cloudadmin> (iwr -Method GET -Uri 'http://$ipAddress/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    {
        "compute":  {
                        "location":  "eastus",
                        "name":  "nt0_0",
                        "offer":  "WindowsServer",
                        "osType":  "Windows",
                        "placementGroupId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "platformFaultDomain":  "0",
                        "platformUpdateDomain":  "0",
                        "publisher":  "MicrosoftWindowsServer",
                        "resourceGroupName":  "sfcluster",
                        "sku":  "2016-Datacenter-with-containers",
                        "subscriptionId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "tags":  "clusterName:sfcluster;resourceType:Service Fabric",
                        "version":  "14393.3443.2001090113",
                        "vmId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        "vmScaleSetName":  "nt0",
                        "vmSize":  "Standard_D2_v2",
                        "zone":  ""
                    },
        "network":  {
                        "interface":  [
                                        "@{ipv4=; ipv6=; macAddress=xxxxxxxxxxxx}"
                                    ]
                    }
    }
#>

[CmdletBinding()]
param(
    $iterations = 1,
    $logFile = "$pwd\azure-metadata-rest.log",
    $sleepMilliseconds = 1000,
    $apiVersion = '2021-02-01' #'2024-06-11',
)

[net.servicePointManager]::Expect100Continue = $true; [net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
$error.Clear()
$ErrorActionPreference = "continue"
$count = 0
$errorCounter = 0

function main() {

    while ($count -le $iterations) {
        # acquire system managed identity oauth token from within node
        $global:managementOauthResultAz = query-metadata -url "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://management.azure.com"

        # key vault
        $global:vaultOauthResultAz = query-metadata -url "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://vault.azure.net"

        # example instance rest query from within node
        $global:instanceResultAz = query-metadata -url "http://169.254.169.254/metadata/instance?api-version=$apiVersion"

        # example scheduledEvents (repair jobs) rest query from within node
        $global:scheduledEventsResult = (Invoke-WebRequest -Method GET `
                -UseBasicParsing `
                -Uri "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" `
                -Headers @{'Metadata' = 'true' }).content | convertfrom-json #| convertto-json

        # example management role (mr) rest query from within node
        $global:managementRoleResult = (Invoke-WebRequest -Method GET `
                -UseBasicParsing `
                -Uri "http://168.63.129.16:80/mrzerosdk").content | convertfrom-json #| convertto-json

        if ($error) {
            if ($logFile) {
                Out-File -InputObject "$(get-date) $($error | Format-List * | out-string)`r`n$result" -FilePath $logFile -Append
            }
            $errorCounter ++
            $error.Clear()
        }

        write-host $global:vaultOauthResult
        write-host $global:managementOauthResult
        write-host ($global:instanceResult | convertto-json -Depth 99)
        write-host ($global:scheduledEventsResult | convertto-json -Depth 99)
        write-host ($global:managementRoleResult | convertto-json -Depth 99)
        start-sleep -Milliseconds $sleepMilliseconds
        $count++
    }

    write-host "objects stored in `$global:managementOauthResult `$global:managementOauthResultAz `$global:vaultOauthResult `$global:vaultOauthResultAz `$global:instanceResult `$global:scheduledeventsresult `$global:managementRoleResult and `$global:instanceResultAz"
    write-host "finished. total errors:$errorCounter logfile:$logFile"
}

function query-metadata($url) {
    $headers = @{'Metadata' = 'true' }
    $irmArgs = @{
        uri     = $url
        method  = 'GET'
        headers = $headers
    }

    if ($PSVersionTable.PSEdition -ieq 'core') {
        $irmArgs.Add('SkipCertificateCheck', $true)
        $irmArgs.Add('SkipHttpErrorCheck', $true)
    }
    else {
        $irmArgs.Add('UseBasicParsing', $true)
    }

    write-host "Invoke-RestMethod $($irmArgs | convertto-json)" -ForegroundColor Green
    $result = Invoke-RestMethod @irmArgs

    write-host "$($result | convertto-json -depth 99)" -ForegroundColor Cyan
    return $result
}

main
