<#
.SYNOPSIS
    Converts tick values in Service Fabric JSON files to timestamps.

.DESCRIPTION
    Reads a Service Fabric JSON file and annotates 18-digit tick values with human-readable timestamp comments.

.NOTES

    File Name  : Convert-JsonTick.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Convert-JsonTick.ps1 -inputFile 'C:\logs\cluster.json'
    Processes the JSON file and adds timestamp annotations for tick values.
#>

[CmdletBinding()]
param(
    $inputFile = "C:\cases\000000000000001\jarvis-nodes-of-a-cluster.json"
)

clear-host
$lines = @([io.file]::ReadAllText($inputFile) -split "\r\n")

foreach($line in $lines)
{
    #look for ticks 131607604784229491
    $pattern = "[0-9]{18}"
    if([regex]::IsMatch($line, $pattern))
    {
        $line -match $pattern | out-null
        $date = (new-object datetime($matches[0].ToString())).ToString("yyMMdd--HH:mm:ss")
        write-host "$($line) // timestamp:$($date)"
    }
    else
    {
        Write-Host $line
    }
}
