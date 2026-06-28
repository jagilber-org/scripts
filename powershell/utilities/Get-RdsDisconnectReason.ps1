<#
.SYNOPSIS
    Returns the friendly description for an RDS disconnect reason code.

.DESCRIPTION
    Looks up a Remote Desktop Services client disconnect reason code (decimal) using the MSTscAx COM object and returns the friendly description.

.NOTES

    File Name  : Get-RdsDisconnectReason.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Get-RdsDisconnectReason.ps1 -disconnectReason 3
    Returns the friendly description for disconnect reason code 3.
#>

[CmdletBinding()]
Param(

    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the disconnect reason code in decimal from client side rds trace")]
    [string] $disconnectReason
    )


$mstsc = New-Object -ComObject MSTscAx.MsTscAx
write-host "description: $($mstsc.GetErrorDescription($disconnectReason,0))"
