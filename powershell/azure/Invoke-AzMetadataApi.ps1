<#
.SYNOPSIS
    Queries the Azure Instance Metadata Service (IMDS) for identity and instance data.

.DESCRIPTION
    Tests Azure VM metadata endpoints for managed identity tokens and instance metadata.
    Runs on a VM scale set node and queries the IMDS REST API at 169.254.169.254.
    Retrieves identity, instance, and attested metadata. Logs results to a file.

.NOTES

    File Name  : Invoke-AzMetadataApi.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Invoke-AzMetadataApi.ps1

.EXAMPLE
    .\Invoke-AzMetadataApi.ps1 -iterations 5 -sleepMilliseconds 2000

.LINK
    https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token
#>
<#
    Script to test azure metadata identity and instance from a configured vm scaleset
    Script runs on vm scaleset node

    to run with no arguments:
    iwr "https://raw.githubusercontent.com/example-user/powershellScripts/master/azure-metadata-rest.ps1" -UseBasicParsing|iex

    or use the following to save and pass arguments:
    invoke-webRequest "https://raw.githubusercontent.com/example-user/powershellScripts/master/azure-metadata-rest.ps1" -outFile "$pwd/azure-metadata-rest.ps1";
    .\azure-metadata-rest.ps1


    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-azure-powershell
    # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-powershell-windows-vmss

    # if needed, enable system / user managed identity on scaleset
    PS C:\Users\example-user> Update-AzVmss -ResourceGroupName sfcluster -Name nt0 -IdentityType "SystemAssigned"


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
        AdminUsername                           : exampleadmin
        WindowsConfiguration                    :
        ProvisionVMAgent                      : True
        EnableAutomaticUpdates                : True
        Secrets[0]                              :
        SourceVault                           :
            Id                                  : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/certs-example/providers/Microsoft.KeyVault/vaults/sf-example
        VaultCertificates[0]                  :
            CertificateUrl                      :
    https://sf-example.vault.azure.net/secrets/sf-example/xxxxxxxxxxxxxxxxxxxxxxxxxxxx
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
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-example-1nt5d/providers/Microsoft.Network/virtualNetworks/VNet/subnets/Subnet-0
            PrivateIPAddressVersion             : IPv4
            LoadBalancerBackendAddressPools[0]  :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-example-1nt5d/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/backendAddressPools/LoadBalancerBEAddressPool                                                                                           LoadBalancerInboundNatPools[0]      :
            Id                                : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-example-1nt5d/providers/Microsoft.Network/loadBalancers/LB-sfcluster-nt0/inboundNatPools/LoadBalancerBEAddressNatPool                                                                                          EnableIPForwarding                    : False
    ExtensionProfile                          :
        Extensions[0]                           :
        Name                                  : nt0_ServiceFabricNode
        Publisher                             : Microsoft.Azure.ServiceFabric
        Type                                  : ServiceFabricNode
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              : {"clusterEndpoint":"https://eastus.servicefabric.azure.com/runtime/cluste                                                                                  rs/00000000-0000-0000-0000-000000000000","nodeTypeRef":"nt0","dataPath":"D:\\\\SvcFab","durabilityLevel":"Bronze","enab                                                                                  leParallelJobs":true,"nicPrefixOverride":"10.0.0.0/24","certificate":{"thumbprint":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","x509StoreName":"My"}} # pii-allowlist # pii-allowlist
        Extensions[1]                           :
        Name                                  : VMDiagnosticsVmExt_vmNodeType0Name
        Publisher                             : Microsoft.Azure.Diagnostics
        Type                                  : IaaSDiagnostics
        TypeHandlerVersion                    : 1.5
        AutoUpgradeMinorVersion               : True
        Settings                              : {"WadCfg":{"DiagnosticMonitorConfiguration":{"overallQuotaInMB":"50000","                                                                                  EtwProviders":{"EtwEventSourceProviderConfiguration":[{"provider":"Microsoft-ServiceFabric-Actors","scheduledTransferKe                                                                                  ywordFilter":"1","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricReliableActorEventT                                                                                  able"}},{"provider":"Microsoft-ServiceFabric-Services","scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestinat                                                                                  ion":"ServiceFabricReliableServiceEventTable"}}],"EtwManifestProviderConfiguration":[{"provider":"00000000-0000-0000-0000-000000000003","scheduledTransferLogLevelFilter":"Information","scheduledTransferKeywordFilter":"4611686018427387904"                                                                                  ,"scheduledTransferPeriod":"PT5M","DefaultEvents":{"eventDestination":"ServiceFabricSystemEventTable"}}]}}},"StorageAcc                                                                                  ount":"examplestorageacct"}
        Extensions[2]                           :
        Name                                  : MMAExtension
        Publisher                             : Microsoft.EnterpriseCloud.Monitoring
        Type                                  : MicrosoftMonitoringAgent
        TypeHandlerVersion                    : 1.0
        AutoUpgradeMinorVersion               : True
        Settings                              :
    {"workspaceId":"00000000-0000-0000-0000-000000000001","stopOnMultipleConnections":"true"}
    ProvisioningState                           : Succeeded
    Overprovision                               : False
    DoNotRunExtensionsOnOverprovisionedVMs      : False
    UniqueId                                    : 00000000-0000-0000-0000-000000000000
    SinglePlacementGroup                        : True
    Identity                                    :
    PrincipalId                               : 00000000-0000-0000-0000-000000000000
    TenantId                                  : 00000000-0000-0000-0000-000000000002
    Type                                      : SystemAssigned
    Id                                          : /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/sf-example-1nt5d/providers/Microsoft.Compute/virtualMachineScaleSets/nt0
    Name                                        : nt0
    Type                                        : Microsoft.Compute/virtualMachineScaleSets
    Location                                    : eastus
    Tags                                        : {"resourceType":"Service Fabric","clusterName":"sfcluster"}


    # acquire system managed identity oauth token from within node
    (iwr -Method GET -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
    PS C:\Users\exampleadmin> (iwr -Method GET -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
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
    (iwr -Method GET -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json

    PS C:\Users\exampleadmin> (iwr -Method GET -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{'Metadata'='true'}).content|convertfrom-json|convertto-json
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
    $apiVersion = "2021-02-01"
)

$error.Clear()
$ErrorActionPreference = "continue"
$count = 0
$errorCounter = 0

while($count -le $iterations) {
    # acquire system managed identity oauth token from within node
    $global:managementOauthResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://management.azure.com" `
        -Headers @{'Metadata'='true'}).content | convertfrom-json #| convertto-json

    $global:vaultOauthResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$apiVersion&resource=https://vault.azure.net" `
        -Headers @{'Metadata'='true'}).content | convertfrom-json #| convertto-json

    # example instance rest query from within node
    $global:instanceResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri "http://169.254.169.254/metadata/instance?api-version=$apiVersion" `
        -Headers @{'Metadata'='true'}).content | convertfrom-json #| convertto-json

    # example scheduledEvents (repair jobs) rest query from within node
    $global:scheduledEventsResult = (Invoke-WebRequest -Method GET `
        -UseBasicParsing `
        -Uri "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" `
        -Headers @{'Metadata'='true'}).content | convertfrom-json #| convertto-json

    if($error) {
        if($logFile) {
            Out-File -InputObject "$(get-date) $($error | fl * | out-string)`r`n$result" -FilePath $logFile -Append
        }
        $errorCounter ++
        $error.Clear()
    }

    write-host $global:vaultOauthResult
    write-host $global:managementOauthResult
    write-host ($global:instanceResult | convertto-json -Depth 99)
    write-host $global:scheduledEventsResult
    start-sleep -Milliseconds $sleepMilliseconds
    $count++
}

write-host "objects stored in `$global:managementOauthResult `$global:vaultOauthResult `$global:scheduledEventsResult and `$global:instanceResult"
write-host "finished. total errors:$errorCounter logfile:$logFile"
