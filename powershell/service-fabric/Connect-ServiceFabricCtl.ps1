<#
.SYNOPSIS
    Connects to a Service Fabric cluster using sfctl (Service Fabric CLI).

.DESCRIPTION
    Authenticates to a Service Fabric cluster endpoint using sfctl with a PEM certificate.
    Verifies sfctl is installed and establishes a cluster connection for CLI-based management.

.NOTES

    File Name  : Connect-ServiceFabricCtl.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Connect-ServiceFabricCtl.ps1 -clusterEndpoint 'https://mycluster.eastus.cloudapp.azure.com:19080' -pemFile './cert.pem'
#>

[CmdletBinding()]
param(
    $clusterEndpoint = 'https://{{cluster}}.{{location}}.cloudapp.azure.com:19080',
    $pemFile = '{{path to pem / key file}}'
)

$PSModuleAutoLoadingPreference = 2
$erroractionpreference = "continue"
$error.Clear()

if(!(sfctl)) {
    write-error "sfctl not installed. see https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cli"

}

$timer = get-date
$error.Clear()
write-host "sfctl cluster show-connection"
$connection = sfctl cluster show-connection
if($error -or !$connection){
    if($clusterEndpoint -and $pemFile) {
        write-host "sfctl cluster select --endpoint $clusterEndpoint --pem $pemFile --no-verify"
        sfctl cluster select --endpoint $clusterEndpoint --pem $pemFile --no-verify
    }
    else {
        write-error "provide `$clusterEndpoint and `$pemfile to select cluster. not connecting to cluster."
        return
    }
}

sfctl cluster show-connection

$totalTime = (get-date) - $timer
write-host "finished: total time: $totalTime"
