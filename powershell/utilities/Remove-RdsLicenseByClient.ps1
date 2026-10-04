<#
.SYNOPSIS
    Revokes an RDS Per-Device CAL license by client name.

.DESCRIPTION
    Revokes a Terminal Services Per-Device Client Access License using the Win32_TSIssuedLicense WMI class. Prompts for the client computer name to revoke.

.NOTES

    File Name  : Remove-RdsLicenseByClient.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Remove-RdsLicenseByClient.ps1
    Lists active licenses and prompts for a client name to revoke.
#>

[CmdletBinding()]
param()

# script to revoke ts perdevice cal
# will prompt for client name to revoke

$activeLicenses = @()
$licenses = get-wmiobject Win32_TSIssuedLicense

#licenseStatus = 4 = revoked, 1 = temp, 2 = 2 permanent
$activelicenses = @($licenses | where {$_.licenseStatus -ne 4})
# status 1 = 1 temp 2 = 2 perm

if($activeLicenses.Count -ge 1)
{
    #$activeLicenses | out-gridview
    $activeLicenses | select sIssuedToComputer | fl

    #sIssuedToComputer for client name
    $clientName = Read-Host 'What client machine do you want to revoke (sIssuedToComputer)?'
    if(![string]::IsNullOrEmpty($clientName))
    {
        foreach ($lic in ($activeLicenses| where {$_.sIssuedToComputer -ieq $clientName}))
        {
            write-host "----------------------------------"
            write-host "removing clientName:$($clientName)"
            $lic.Revoke() | select ReturnValue, RevokableCals, NextRevokeAllowedOn | fl
            break
        }
    }
}
else
{
    write-host "no licenses to revoke"
}

write-host "finished"
