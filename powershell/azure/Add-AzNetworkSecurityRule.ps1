<#
.SYNOPSIS
    Adds a priority-100 NSG rule for remote access to Azure resources.

.DESCRIPTION
    Creates or updates a Network Security Group inbound rule to allow remote access
    (RDP, SSH, or custom ports) to Azure resources in a resource group. Uses Azure
    service tags for source address filtering.

.NOTES

    File Name  : Add-AzNetworkSecurityRule.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Add-AzNetworkSecurityRule.ps1 -resourceGroup 'myRG'

.LINK
    https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview
#>

[CmdletBinding()]

param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup = '',
    [string]$nsgRuleName = "remote-rule",
    [int]$priority = 100,
    [string[]]$destPorts = @('*'), #@('3389', '19000', '19080', '19081', '22'),
    [string[]]$existingNsgNames = @(),
    [ValidateSet('allow','deny')]
    [string]$access = "Allow",
    [ValidateSet('inbound','outbound')]
    [string]$direction = "inbound",
    [string[]]$sourceAddressPrefix = @(((Invoke-RestMethod https://ipinfo.io/json).ip)), #,'*','AzureDevOps','AzureTrafficManager','ServiceFabric'), # *
    [string[]]$destAddressPrefix = @('*'), #,'*','AzureDevOps','AzureTrafficManager','ServiceFabric'), # *
    [switch]$force,
    [switch]$remove,
    [switch]$wait
)

function main () {
    $waitCount = 0

    while ($wait -or $waitCount -eq 0) {
        if (!$existingNsgNames) {
            $existingNsgNames = @((get-aznetworksecuritygroup -resourcegroupname $resourceGroup).Name)
        }

        foreach ($nsgName in $existingNsgNames) {
            if ([string]::IsNullOrEmpty($nsgName)) { continue }
            $nsg = get-nsg $nsgName
            if (!$nsg) {
                Write-Warning "unable to find $nsgName"
                continue
            }

            modify-nsgRule $nsg
            $waitCount++
        }

        if ($wait -and $waitCount -eq 0) {
            Write-Host "$waitCount waiting for nsg $(get-date)"
            Start-Sleep -Seconds 60
        }
        else {
            break
        }
    }
    write-host "finished"
}

function get-nsg($name) {
    $nsg = Get-AzNetworkSecurityGroup -Name $name -ResourceGroupName $resourceGroup
    if (!$nsg) {
        Write-Warning "no nsg $nsgname`r`nreturning"
        return $false
    }
    return $nsg
}

function modify-nsgRule($nsg) {
    $currentRule = Get-AzNetworkSecurityRuleConfig -Name $nsgRuleName -NetworkSecurityGroup $nsg -ErrorAction SilentlyContinue

    if ($currentRule -and ($force -or $remove)) {
        Write-Warning "deleting existing rule`r`n$($currentRule | convertto-json -depth 5)"
        Remove-AzNetworkSecurityRuleConfig -Name $nsgRuleName -NetworkSecurityGroup $nsg
    }
    elseif ($currentRule) {
        Write-Warning "$nsgRuleName exists`r`nreturning"
        return
    }
    elseif (!$currentRule -and $remove) {
        Write-Warning "$nsgRuleName does not exist`r`nreturning"
        return
    }

    write-host "adding rule:
    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName ``
        -NetworkSecurityGroup $nsg ``
        -Description $nsgRuleName ``
        -Access $access ``
        -Protocol Tcp ``
        -Direction $direction ``
        -Priority $priority ``
        -SourceAddressPrefix $sourceAddressPrefix ``
        -SourcePortRange * ``
        -DestinationAddressPrefix $destAddressPrefix ``
        -DestinationPortRange $destPorts
    " -ForegroundColor Green

    Add-AzNetworkSecurityRuleConfig -Name $nsgRuleName `
        -NetworkSecurityGroup $nsg `
        -Description $nsgRuleName `
        -Access $access `
        -Protocol Tcp `
        -Direction $direction `
        -Priority $priority `
        -SourceAddressPrefix $sourceAddressPrefix `
        -SourcePortRange * `
        -DestinationAddressPrefix $destAddressPrefix `
        -DestinationPortRange $destPorts

    write-host "setting rule: Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg" -ForegroundColor Green
    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
}

main
