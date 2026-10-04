<#
.SYNOPSIS
    powershell script to connect to replace managed service fabric cluster primary nodetype

.DESCRIPTION
    Replaces the primary node type of a Service Fabric managed cluster by adding a new
    node type, migrating workloads, and removing the old primary.

.NOTES

    File Name  : Update-ServiceFabricManagedPrimary.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Update-ServiceFabricManagedPrimary.ps1 -clusterName 'myCluster' -resourceGroupName 'myRG'

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-replace-primary.ps1" -outFile "$pwd/sf-managed-replace-primary.ps1";
    ./sf-managed-replace-primary.ps1 -clusterEndpoint <cluster endpoint fqdn> -thumbprint <thumbprint>
#>
[CmdletBinding()]
param(
    [string]$resourceGroupName = '',
    [string]$json = "$pwd\current.json",
    [string]$clusterName = $resourceGroupName, #"mysfcluster",
    [string]$newNodeTypeName = "nt2",
    [string]$oldNodeTypeName = "nt1",
    [string]$vmSize = "Standard_D2_v2",
    [int]$instanceCount = 5,
    [bool]$isPrimary = $true,
    [switch]$whatIf
)
$ErrorActionPreference = 'Stop'
#export template
export-azresourcegroup -SkipAllParameterization -ResourceGroupName $resourceGroupName -Path $json #-Force

write-host "New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName ``
    -ClusterName $clusterName ``
    -Name $newNodeTypeName ``
    -InstanceCount $instanceCount ``
    -vmSize $vmSize ``
    -primary:$isPrimary
"

if (!$whatIf) {
    # add new node type
    New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName `
        -ClusterName $clusterName `
        -Name $newNodeTypeName `
        -InstanceCount $instanceCount `
        -vmSize $vmSize `
        -primary:$isPrimary
}

write-host "Remove-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName ``
    -ClusterName $clusterName ``
    -Name $oldNodeTypeName
"

if (!$whatIf) {
    # remove old node type
    Remove-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName `
        -ClusterName $clusterName `
        -Name $oldNodeTypeName
}

write-host 'finished'
