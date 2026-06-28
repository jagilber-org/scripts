<#
.SYNOPSIS
    One-time sync of extensions from stable Visual Studio Code to VS Code Insiders.

.DESCRIPTION
    Exports the list of installed extensions from the stable "code" CLI and installs any
    missing extensions into VS Code Insiders ("code-insiders" CLI). Skips those already
    installed, logs actions, and provides a summary.

.NOTES
    Author: Automated script generation
    Run:   PowerShell 7+ (pwsh) recommended
    Safe:  Does not uninstall or modify existing Insiders extensions.

.EXAMPLE
    # Basic run (installs any missing extensions into Insiders)
    ./Sync-VSCodeExtensionsToInsiders.ps1

.EXAMPLE
    # Pin versions based on current stable versions
    ./Sync-VSCodeExtensionsToInsiders.ps1 -UsePinnedVersions

.EXAMPLE
    # Dry run to see what would install
    ./Sync-VSCodeExtensionsToInsiders.ps1 -WhatIf

.PARAMETER StableCommand
    Command used to invoke stable VS Code CLI (default: code)

.PARAMETER InsidersCommand
    Command used to invoke VS Code Insiders CLI (default: code-insiders)

.PARAMETER UsePinnedVersions
    If specified, uses --show-versions output and attempts to install exact versions.

.PARAMETER OutputListPath
    Optional path to write out the canonical stable extensions list (with versions if pinned).

.PARAMETER Verbose
    Standard PowerShell switch to emit extra detail.

#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$StableCommand = 'code',
    [string]$InsidersCommand = 'code-insiders',
    [switch]$UsePinnedVersions,
    [string]$OutputListPath
)

Write-Verbose "Stable CLI: $StableCommand"
Write-Verbose "Insiders CLI: $InsidersCommand"

function Test-CliPresent {
    param([string]$Command)
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command '$Command' not found in PATH. Launch that edition once and ensure 'Shell Command: Install code command' is enabled."
    }
}

Test-CliPresent -Command $StableCommand
Test-CliPresent -Command $InsidersCommand

$timeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir    = Join-Path $env:TEMP 'vscode-sync'
$null = New-Item -ItemType Directory -Force -Path $logDir
$logPath  = Join-Path $logDir "sync-$timeStamp.log"

Write-Host "Exporting stable extensions..." -ForegroundColor Cyan
$stableRaw = if ($UsePinnedVersions) { & $StableCommand --list-extensions --show-versions } else { & $StableCommand --list-extensions }
if (-not $stableRaw) {
    Write-Warning 'No extensions found in stable VS Code. Exiting.'
    return
}

# Build hashtable for version lookups when pinned
$stableVersionMap = @{}
if ($UsePinnedVersions) {
    foreach ($line in $stableRaw) {
        $parts = $line -split '@'
        $name  = $parts[0]
        $ver   = if ($parts.Length -gt 1) { $parts[1] } else { $null }
        $stableVersionMap[$name] = $ver
    }
    $stableList = $stableVersionMap.Keys
} else {
    $stableList = $stableRaw
}

if ($OutputListPath) {
    $dir = Split-Path -Parent $OutputListPath
    if ($dir -and -not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    if ($UsePinnedVersions) {
        $stableRaw | Sort-Object | Set-Content -Encoding UTF8 $OutputListPath
    } else {
        $stableList | Sort-Object | Set-Content -Encoding UTF8 $OutputListPath
    }
    Write-Host "Wrote extension list to $OutputListPath" -ForegroundColor DarkCyan
}

Write-Host "Exporting Insiders extensions..." -ForegroundColor Cyan
$insidersList = & $InsidersCommand --list-extensions

$toInstall = $stableList | Where-Object { $insidersList -notcontains $_ }
if (-not $toInstall) {
    Write-Host 'All stable extensions already present in Insiders. Nothing to install.' -ForegroundColor Green
    return
}

Write-Host "Need to install $($toInstall.Count) extension(s)." -ForegroundColor Yellow

$results = @()
foreach ($ext in $toInstall) {
    $display = $ext
    $target  = $ext
    if ($UsePinnedVersions -and $stableVersionMap[$ext]) {
        $target = "$ext@$($stableVersionMap[$ext])"
        $display = $target
    }
    if ($PSCmdlet.ShouldProcess($display,'Install into VS Code Insiders')) {
        Write-Host "Installing $display" -ForegroundColor White
        $output = & $InsidersCommand --install-extension $target 2>&1
        $output | Tee-Object -FilePath $logPath -Append | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $results += [PSCustomObject]@{Extension=$display;Status='Installed'}
        } else {
            $joined = $output -join ' '
            if ($joined -match 'is already installed') {
                $results += [PSCustomObject]@{Extension=$display;Status='AlreadyInstalled'}
            } elseif ($joined -match 'not found') {
                $results += [PSCustomObject]@{Extension=$display;Status='NotFound';Message=$joined}
            } else {
                $results += [PSCustomObject]@{Extension=$display;Status='Failed';Message=$joined}
            }
        }
    }
}

Write-Host "\nSummary:" -ForegroundColor Cyan
$results | Sort-Object Status, Extension | Format-Table -AutoSize

$failed = $results | Where-Object { $_.Status -in @('Failed','NotFound') }
$notFound = $results | Where-Object Status -eq 'NotFound'
if ($failed) {
    if ($notFound) {
        Write-Warning "Some extensions not found in Marketplace (check naming or deprecation): $(($notFound.Extension -join ', '))"
    }
    $other = $results | Where-Object Status -eq 'Failed'
    if ($other) { Write-Warning "Some extensions failed for other reasons: $(($other.Extension -join ', '))" }
    Write-Warning "See log: $logPath"
} else {
    Write-Host "All requested extensions installed or already present. Log: $logPath" -ForegroundColor Green
}

# Return objects for script consumption (e.g., CI)
$results
