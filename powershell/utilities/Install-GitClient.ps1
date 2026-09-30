<#
.SYNOPSIS
    Downloads and installs the Git client.

.DESCRIPTION
    Downloads and installs the Git client or GitHub CLI from GitHub releases. Supports minimal Git, path configuration, forced reinstall, and cleanup.

.NOTES

    File Name  : Install-GitClient.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Install-GitClient.ps1
    Downloads and installs the latest Git client.

.EXAMPLE
    .\Install-GitClient.ps1 -hub
    Downloads and installs the GitHub CLI.
#>

[CmdletBinding()]
param(
    [string]$destPath = "c:\program files", #$pwd, # $env:appdata
    [switch]$setPath,
    [switch]$gitMinClient,
    [switch]$hub,
    [switch]$clean,
    [switch]$force,
    [string]$gitReleaseApi = "https://api.github.com/repos/git-for-windows/git/releases/latest",
    [string]$hubReleaseApi = "https://api.github.com/repos/cli/cli/releases/latest", #"https://api.github.com/repos/github/hub/releases/latest",
    [string]$gitClientType = "Git-.+?-64-bit.exe",
    [string]$hubClientType = "gh_.+?_windows_amd64.zip", #"hub-windows-amd64-.+?.zip",
    [string]$minGitClientType = "mingit.+64"
)

[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
$erroractionpreference = "continue"
$error.clear()

function main() {

    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        if(!$force) {
            Write-Warning "restart in admin powershell or use -force"
            return
        }

        if($destpath -ieq "c:\program files"){
            Write-Warning "not in admin powershell session. setting path from $destpath to $pwd"
            $destpath = $pwd.tostring()
        }
    }

    $destpath = $destpath.replace("\\","\").TrimEnd("\")

    if ($hub) {
        Set-Alias git gh
        $gitClientType = $hubClientType
        $gitReleaseApi = $hubReleaseApi
        $destPath = "$destPath\cli"
    }
    else {
        $destPath = "$destPath\Git"
    }

    $binPath = $destPath.ToLower() + "\bin"

    if ($gitMinClient) {
        $gitClientType = $minGitClientType
        $binPath = $destPath.tolower() + "\mingw32\bin"
    }

    write-host "binpath: $binpath" -ForegroundColor Green

    (git) | out-null

    if ($error -and $clean) {
        write-warning "git already removed"
        return
    }

    if (!$error -and !$force -and !$clean) {
        write-warning "git already installed. use -force"
        return
    }

    $error.clear()
    $path = [environment]::GetEnvironmentVariable("Path")

    if ($clean) {
        if ($path.tolower().contains($binPath)) {
            [environment]::SetEnvironmentVariable("Path", $($path.replace(";$($binPath)", "")), "Machine")
        }

        remove-install
        write-host "cleaned..."
        return
    }

    # -usebasicparsing deprecated but needed for nano / legacy
    $apiResults = convertfrom-json (Invoke-WebRequest $gitReleaseApi -UseBasicParsing)
    $downloadUrl = @($apiResults.assets -imatch $gitClientType)[0].browser_download_url

    if (!$downloadUrl) {
        $apiResults
        write-warning "unable to find download url"
        return
    }

    $downloadUrl
    #$clientFile = "$($destPath)\gitfullclient.zip"
    $clientFile = "$($destPath)\$([io.path]::GetFileName($downloadUrl))"

    if ($force) {
        remove-install
    }

    mkdir $destPath

    if (!(test-path $clientFile) -or $force) {
        if ($force) {
            remove-item $clientFile
        }

        write-host "downloading $downloadUrl to $clientFile"
        #invoke-webRequest $downloadUrl -outFile  $clientFile
        [net.webclient]::new().DownloadFile($downloadUrl, $clientFile)
    }

    if ($clientFile -imatch ".zip") {
        Expand-Archive $clientFile $destPath
    }
    else {
        # install
        $argumentList = "/SP- /SILENT /SUPPRESSMSGBOXES /LOG=git-install.log /NORESTART /CLOSEAPPLICATIONS"
        write-host "$clientFile $argumentList"
        start-process -FilePath $clientFile -ArgumentList $argumentList -Wait

        if (!(test-path $binPath)) {
            write-warning "unable to find $binPath"
            $binPath = $null
        }
    }

    if ($binPath -and !$path.tolower().contains($binPath)) {
        write-host "setting path"
        $env:Path = $env:Path.TrimEnd(";") + ";$($binPath)"

        if ($setPath) {
            write-host "setting path permanent"
            [environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$($binPath)", "Machine")
        }
    }
    else {
        write-host "path contains $binPath"
    }

    write-host $env:path
    write-host "finished"
}

function remove-install()
{
    if ((test-path $destPath)) {
        $uninstallFile = @([io.directory]::GetFiles("$destpath","unins*.exe"))[-1]
        if ($uninstallFile) {
            Write-Warning "running uninstall"
            Start-Process $uninstallFile -Wait
        }

        remove-item $destPath -Force -Recurse
    }
}

main
