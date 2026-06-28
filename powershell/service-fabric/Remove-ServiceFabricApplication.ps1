<#
.SYNOPSIS
    Removes a Service Fabric application, unregisters its type, and cleans up packages.

.DESCRIPTION
    Connects to a Service Fabric cluster and performs a complete application removal:
    removes the application instance, unregisters the application type, removes the
    image store package, and removes named services.

.NOTES

    File Name  : Remove-ServiceFabricApplication.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Remove-ServiceFabricApplication.ps1
#>

[CmdletBinding()]
param()

$thumbprint = "0123456789012345678901234567890123456789" # pii-allowlist
$fabricApplicationName = "fabric:/Watchdog"
$fabricApplicationNameType = "fabric:/WatchdogType"
$fabricServiceName = "fabric:/WatchdogType/WatchdogService"
$applicationVersion = "1.0.0"
$applicationTypeName = "WatchdogType"

Connect-ServiceFabricCluster -ConnectionEndpoint "10.0.0.4:19000" -X509Credential -ServerCertThumbprint $thumbprint -FindType FindByThumbprint -FindValue $thumbprint -verbose -StoreLocation CurrentUser

Remove-ServiceFabricApplication -ApplicationName $fabricApplicationName

Remove-ServiceFabricApplication -ApplicationName $fabricApplicationNameType
Unregister-ServiceFabricApplicationType -ApplicationTypeName $applicationTypeName -ApplicationTypeVersion $applicationVersion -Verbose
Remove-ServiceFabricApplicationPackage -ApplicationPackagePathInImageStore $fabricApplicationNameType -Verbose
Remove-ServiceFabricService -ServiceName $fabricServiceName -Verbose
