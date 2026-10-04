<#
.SYNOPSIS
    Queries Azure Service Fabric Resource Provider (SFRP) REST API.

.DESCRIPTION
    Sends ARM REST API requests to the Service Fabric resource provider endpoints
    to query cluster information, node types, and other SFRP resources.

.NOTES

    File Name  : Invoke-ServiceFabricRestQuery.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Invoke-ServiceFabricRestQuery.ps1 -resourceGroup 'myRG' -clusterName 'myCluster'

.LINK
    https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-api-clusters_get
#>

[CmdletBinding()]
param(
    [object]$token = $global:token,
    [string]$SubscriptionID = "$(@(Get-AzureRmSubscription)[0].Id)",
    [string]$baseURI = "https://management.azure.com" ,
    [string]$apiVersion = "?api-version=2018-02-01" ,
    [string]$resourceGroup,
    [string]$clusterName
)


if ($resourceGroup -and $clusterName)
{
    [string]$SubscriptionURI = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($resourceGroup)/providers/Microsoft.ServiceFabric/clusters/$($clusterName)" + $apiVersion
}
else
{
    [string]$SubscriptionURI = $baseURI + "/subscriptions/$($SubscriptionID)/providers/Microsoft.ServiceFabric/clusters" + $apiVersion
}


$uri = $SubscriptionURI
$uri


$Body = @{
    'client_id' = $applicationId
}
$params = @{
    ContentType = 'application/x-www-form-urlencoded'
        Headers = @{
            'authorization' = "Bearer $($token.access_token)"
                   'accept' = 'application/json'
    }
         Method = 'Get'
            uri = $uri
           Body = $Body
}

$params
$params.Body.client_id
$params.Headers.authorization

$response = Invoke-RestMethod @params -Verbose -Debug
$response | convertto-json

$global:response = $response
$response
$global:response
$global:response.value.properties | ConvertTo-Json
