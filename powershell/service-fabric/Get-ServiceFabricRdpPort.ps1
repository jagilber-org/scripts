<#
.SYNOPSIS
    Enumerates RDP port mapping from cluster load balancer for a Service Fabric VMSS.

.DESCRIPTION
    Queries the Azure load balancer inbound NAT rules to determine the RDP port
    mapping for each Service Fabric scale set node.

.NOTES

    File Name  : Get-ServiceFabricRdpPort.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Get-ServiceFabricRdpPort.ps1 -resourcegroup 'myRG'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    $resourcegroup
)

write-host "checking resource group $resourceGroup"
$lbs = Get-AzureRmLoadBalancer -ResourceGroupName $resourcegroup
$cluster = Get-AzureRmServiceFabricCluster -ResourceGroupName $resourcegroup
$clusterfqdn = [regex]::Match($cluster.ManagementEndpoint,"http.://(.+?):").Groups[1].Value

foreach($rule in $lbs.InboundNatRules)
{
    $frontEndPort = $rule.FrontendPort
    $nicId = convertfrom-json $rule.BackendIPConfigurationText
    $matches = [regex]::Match($nicId.Id,"/virtualMachineScaleSets/(?<nodeTypeName>.+?)/virtualMachines/(?<instanceId>.+?)/networkInterfaces")
    $instanceId = $matches.Groups['instanceId'].Value
    $nodeTypeName = $matches.Groups['nodeTypeName'].Value
    $vmssvm = Get-AzureRmVmssVM -ResourceGroupName $resourcegroup -VMScaleSetName $nodeTypeName -InstanceId $instanceId

    "$($vmssvm.name): mstsc /v $($clusterfqdn):$($frontEndPort)"
}

write-host "finished"
