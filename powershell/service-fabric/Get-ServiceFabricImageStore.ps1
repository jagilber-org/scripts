<#
.SYNOPSIS
# script to enumerate azure service fabric imagestore
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings

.DESCRIPTION
    Enumerates the Service Fabric image store contents including application packages,
    versions, and sizes. Helps identify stale packages for cleanup.

.NOTES

    File Name  : Get-ServiceFabricImageStore.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Get-ServiceFabricImageStore.ps1 -resourceGroup 'myRG' -clusterName 'myCluster'

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-fabric-imagestore-enumeration.ps1" -outFile "$pwd\azure-az-sf-fabric-imagestore-enumeration.ps1";
.\azure-az-sf-fabric-imagestore-enumeration.ps1

#>

[CmdletBinding()]
param (
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

function main () {
    if (!(get-command connect-servicefabriccluster)) { import-module servicefabric }
    connect-servicefabriccluster

    write-host "get-storeInfo -recurse"
    get-storeInfo -recurse
    write-host 'finished'
}

function get-storeInfo([string]$relativePath = '', [switch]$recurse) {
    $results = [collections.arraylist]::new(@((Get-ServiceFabricImageStoreContent -ImageStoreConnectionString 'fabric:ImageStore' -RemoteRelativePath $relativePath)))
    if ($recurse) {
        foreach($result in [collections.arraylist]::new($results)) {
            if($result.Type -ieq 'File') {
                continue
            }
           [void]$results.AddRange(@(get-storeInfo -relativePath $result.StoreRelativePath -recurse:$recurse))
        }
    }
    return $results
}

main
