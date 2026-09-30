<#
.SYNOPSIS
script to monitor docker named pipe

.DESCRIPTION
    Monitors the Docker named pipe (npipe) connection status on a Service Fabric node.
    Loops continuously attempting to connect and reporting status.

.NOTES

    File Name  : Connect-ServiceFabricDockerNamedPipe.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Connect-ServiceFabricDockerNamedPipe.ps1

.LINK
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-namedpipe-connect.ps1","$pwd\sf-docker-namedpipe-connect.ps1");
.\sf-docker-namedpipe-connect.ps1;
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'continue'
while ($true) {
    try {
        Start-Sleep -Seconds 1
        [io.pipes.NamedPipeClientStream] $pipeClient = new-object io.pipes.NamedPipeClientStream(".", "docker_engine", [io.pipes.PipeDirection]::InOut)
        Write-host "Attempting to connect to pipe..."
        $pipeClient.Connect(10000)
        write-host "access control: $($pipeClient.GetAccessControl() | fl * | out-string)"
        write-host "access: $($pipeClient.GetAccessControl().Access | fl * | out-string)"
        write-host "pipeclient: `r`n$($pipeClient | convertto-json -depth 99)"
    }
    catch {
        Write-Warning 'unable to connect'
    }
    finally {
        if ($pipeClient) {
            $pipeClient.Close()
        }
    }
}
