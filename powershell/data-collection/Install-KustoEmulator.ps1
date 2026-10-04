<#
.SYNOPSIS
    Installs and runs the Azure Data Explorer (Kusto) emulator using Docker.

.DESCRIPTION
    Pulls and runs the Azure Data Explorer Kustainer Docker image for local development
    and testing. Verifies Docker is installed and running, checks for existing emulator instances,
    and launches the emulator with configurable port mapping and memory allocation.

.NOTES

    File Name  : Install-KustoEmulator.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.PARAMETER dockerImage
    The Docker image name to use. Default: 'mcr.microsoft.com/azuredataexplorer/kustainer'.

.PARAMETER imageVersion
    The image version tag. Default: 'latest'.

.PARAMETER portMapping
    Docker port mapping in the format 'host:container'. Default: '8080:8080'.

.PARAMETER memGB
    Memory limit for the Docker container. Default: '4GB'.

.EXAMPLE
    .\Install-KustoEmulator.ps1
    Installs and runs the Kusto emulator with default settings on port 8080.

.EXAMPLE
    .\Install-KustoEmulator.ps1 -portMapping '9090:8080' -memGB '8GB'
    Runs the emulator on port 9090 with 8GB memory allocation.

.LINK
    https://mcr.microsoft.com/en-us/product/azuredataexplorer/kustainer/about
#>
[CmdletBinding()]
param(
  $dockerImage = 'mcr.microsoft.com/azuredataexplorer/kustainer',
  $imageVersion = 'latest',
  $portMapping = '8080:8080',
  $memGB = '4GB'
)

function main() {
  $dockerImageVersion = "$($dockerImage):$imageVersion"
  $error.clear()
  # verify docker is installed
  write-host "docker --version"
  $dockerVersion = docker --version
  if ($error -or ($dockerVersion -eq $null)) {
    write-error "docker is not installed. Please install docker and try again. $dockerVersion"
    return
  }
  else {
    write-host "docker version: $dockerVersion" -ForegroundColor Green
  }

  # verify docker is running
  write-host "docker info"
  $dockerStatus = docker info
  if ($error -or ($dockerStatus -eq $null) -or ($dockerStatus.tostring().startswith('error:'))) {
    write-error "docker is not running. Please start docker and try again. $dockerStatus"
    return
  }
  else {
    write-host "docker is running." -foregroundcolor Green
  }

  # see if kusto emulator is already running
  write-host "docker ps -a"
  $kustoEmulatorStatus = docker ps -a
  if ($kustoEmulatorStatus -imatch "$($dockerImage).+Up ") {
    write-host "Kusto Emulator is already running." -foregroundcolor Green
    return
  }
  else {
    write-host "Kusto Emulator is not running." -foregroundcolor yellow
  }

  write-host $kustoEmulatorStatus

  # see if kusto emulator image is already downloaded
  write-host "docker images"
  $kustoEmulatorImage = docker images
  if ($kustoEmulatorImage -imatch $dockerImage) {
    write-host "Kusto Emulator image is already downloaded." -foregroundcolor Green
  }
  else {
    write-host "Downloading Kusto Emulator image." -foregroundcolor yellow

    # pull the docker image
    write-host "docker pull $dockerImageVersion" -foregroundcolor yellow
    docker pull $dockerImageVersion
  }

  # run the docker image
  write-host "docker run -e ACCEPT_EULA=Y -m $memGB -d -p $portMapping -t $dockerImageVersion" -foregroundcolor yellow
 docker run -e ACCEPT_EULA=Y -m $memGB -d -p $portMapping -t $dockerImageVersion
}

main
