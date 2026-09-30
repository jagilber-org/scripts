<#
.SYNOPSIS
# script to update azure service fabric settings for imagestore best practice
# https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-fabric-settings

.DESCRIPTION
    Configures recommended image store cleanup settings on an Azure Service Fabric cluster.
    Sets CleanupApplicationPackageOnProvisionSuccess and related parameters.

.NOTES

    File Name  : Set-ServiceFabricImageStoreSettings.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Set-ServiceFabricImageStoreSettings.ps1 -resourceGroup 'myRG' -clusterName 'myCluster'

.LINK
(new-object net.webclient).DownloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-set-fabric-imagestore-settings.ps1","$pwd\azure-az-sf-set-fabric-imagestore-settings.ps1")
.\azure-az-sf-set-fabric-imagestore-settings.ps1 -resourceGroup {{cluster resource group}} -clusterName {{cluster name}}

#>

[CmdletBinding()]
param (
    [string]$resourceGroup = '',
    [string]$clusterName = '',
    [string]$fabricSettingsJson = '',
    [hashtable]$fabricSettings = @{
        Management = @{
            CleanupApplicationPackageOnProvisionSuccess = $true
            CleanupUnusedApplicationTypes = $true
            PeriodicCleanupUnusedApplicationTypes = $true
            TriggerAppTypeCleanupOnProvisionSuccess = $true
            MaxUnusedAppTypeVersionsToKeep = 3
        }
    }
)

function main () {
    $fabricSettingsArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription]]::new()

    if(!$resourceGroup -or !$clusterName -or !($fabricSettingsJson -or $fabricSettings)) {
        write-error 'pass arguments'
        return
    }

    if (!(@(Get-AzResourceGroup).Count)) {
        Connect-AzAccount
    }

    $error.Clear()
    $global:currentSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
    write-host "current settings: `r`n $global:currentSettings" -ForegroundColor Green
    write-host "current fabric settings"
    $currentSettings.FabricSettings
    if($error) {
        Write-Warning "error enumerating cluster"
        return
    }

    write-host "updating fabric settings" -foregroundcolor yellow
    write-host "using fabric settings array for one ud walk"

    if($fabricSettingsJson) {
        $error.Clear()
        write-host ($fabricSettingsJson | convertfrom-json | convertto-json) -ForegroundColor Green
        $fabricSettings = $fabricSettingsJson | convertfrom-json

        if($error) {
            Write-Warning "error converting json"
            return
        }

        foreach($fabricSetting in $fabricSettings) {
            $fabricParametersArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription]]::new()
            $sectionDescription = new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription
            $sectionDescription.name = $fabricSetting.name

            foreach($setting in $fabricSetting.parameters) {
                $fabricParametersArray.Add((add-parameter -name $setting.name -value $setting.value))
            }

            $sectionDescription.parameters = $fabricParametersArray
            $fabricSettingsArray.Add($sectionDescription)
        }

    }
    else {
        foreach($fabricSetting in $fabricSettings.GetEnumerator()) {
            $fabricParametersArray = [collections.Generic.List[Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription]]::new()
            $sectionDescription = new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsSectionDescription
            $sectionDescription.name = $fabricSetting.Key

            foreach($setting in $fabricSetting.Value.GetEnumerator()) {
                $fabricParametersArray.Add((add-parameter -name $setting.name -value $setting.value))
            }

            $sectionDescription.parameters = $fabricParametersArray
            $fabricSettingsArray.Add($sectionDescription)
        }
    }
    $fabricSettingsArray

    write-host "Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
            -Name $clusterName `
            -SettingsSectionDescription $fabricSettingsArray"

    Set-AzServiceFabricSetting -ResourceGroupName $resourceGroup `
        -Name $clusterName `
        -SettingsSectionDescription $fabricSettingsArray

    $global:newSettings = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clusterName
    write-host "new settings: `r`n $global:newSettings" -ForegroundColor Cyan
    write-host "new fabric settings"

    $currentSettings.FabricSettings
    write-host 'finished'
}

function add-parameter([string]$name, $value) {
    return (new-object Microsoft.Azure.Commands.ServiceFabric.Models.PSSettingsParameterDescription -property @{
        name  = $name
        value = $value
    })
}

main
