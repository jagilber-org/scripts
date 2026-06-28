<#
.SYNOPSIS
    Optional Layer 3 sub-check: Invoke Gitleaks for community-maintained pattern coverage.

.DESCRIPTION
    This script wraps Gitleaks as a supplemental scanner alongside the custom regex patterns
    in Test-PreCommitPii.ps1. It is NOT a replacement for the custom scanner — Layers 1 and 2
    (forbidden files and value matching) remain PowerShell-native.

    Gitleaks provides ~800+ community-maintained detection rules that complement
    the custom patterns. This hybrid approach combines:
      - Custom Layer 2 (unique: matches YOUR actual secret values from central .env)
      - Custom Layer 3 patterns (org-specific rules)
      - Gitleaks (broad community patterns for vendor-specific secrets)

.PARAMETER StagedOnly
    Scan only staged (cached) changes. Default for pre-commit use.

.PARAMETER ReportPath
    Path to write the Gitleaks JSON report. Default: temp file.

.PARAMETER GitleaksPath
    Path to gitleaks binary. Default: searches PATH.

.PARAMETER Install
    Download and install gitleaks if not found.

.EXAMPLE
    .\Invoke-GitleaksScan.ps1
    # Scan staged changes

.EXAMPLE
    .\Invoke-GitleaksScan.ps1 -Install
    # Install gitleaks first, then scan

.NOTES
    Gitleaks: https://github.com/gitleaks/gitleaks
    This is OPTIONAL — the core scanner works without it.
    Version    : 1.0.0
    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)

#>

[CmdletBinding()]
param(
    [switch]$StagedOnly = $true,
    [string]$ReportPath,
    [string]$GitleaksPath,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Find or Install Gitleaks
function Find-Gitleaks {
    if ($GitleaksPath -and (Test-Path $GitleaksPath)) {
        return $GitleaksPath
    }

    # Check PATH
    $found = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($found) {
        return $found.Source
    }

    # Check common locations
    $commonPaths = @(
        "$env:USERPROFILE\.gitleaks\gitleaks.exe"
        "$env:USERPROFILE\go\bin\gitleaks.exe"
        "/usr/local/bin/gitleaks"
        "$env:LOCALAPPDATA\gitleaks\gitleaks.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

function Install-Gitleaks {
    Write-Host "Installing gitleaks..." -ForegroundColor Cyan

    if ($IsWindows -or $env:OS -match 'Windows') {
        # Windows: use winget or direct download
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            winget install --id Gitleaks.Gitleaks --accept-package-agreements --accept-source-agreements
            return (Get-Command gitleaks -ErrorAction SilentlyContinue).Source
        }

        # Fallback: direct download from GitHub releases
        $installDir = "$env:LOCALAPPDATA\gitleaks"
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

        $releaseUrl = "https://api.github.com/repos/gitleaks/gitleaks/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'PowerShell' }
        $asset = $release.assets | Where-Object { $_.name -match 'windows_amd64\.zip$' } | Select-Object -First 1

        if (-not $asset) {
            Write-Error "Could not find gitleaks release for Windows amd64"
            return $null
        }

        $zipPath = Join-Path $env:TEMP "gitleaks.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
        Remove-Item $zipPath -Force

        $exePath = Join-Path $installDir "gitleaks.exe"
        if (Test-Path $exePath) {
            Write-Host "Installed gitleaks to: $exePath" -ForegroundColor Green
            return $exePath
        }
    } else {
        # Linux/macOS: use brew or direct download
        $brew = Get-Command brew -ErrorAction SilentlyContinue
        if ($brew) {
            brew install gitleaks
            return (Get-Command gitleaks -ErrorAction SilentlyContinue).Source
        }

        Write-Error "Please install gitleaks manually: https://github.com/gitleaks/gitleaks#installing"
    }

    return $null
}
#endregion

#region Main
$gitleaksExe = Find-Gitleaks

if (-not $gitleaksExe) {
    if ($Install) {
        $gitleaksExe = Install-Gitleaks
        if (-not $gitleaksExe) {
            Write-Error "Failed to install gitleaks"
            exit 1
        }
    } else {
        Write-Host "⚠️ Gitleaks not found — skipping supplemental scan" -ForegroundColor Yellow
        Write-Host "   Install with: .\Invoke-GitleaksScan.ps1 -Install" -ForegroundColor DarkYellow
        Write-Host "   Or: winget install Gitleaks.Gitleaks" -ForegroundColor DarkYellow
        exit 0  # non-blocking — gitleaks is optional
    }
}

# Set up report path
if (-not $ReportPath) {
    $ReportPath = Join-Path $env:TEMP "gitleaks-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
}

# Build gitleaks arguments
$gitleaksArgs = @(
    'detect'
    '--report-format', 'json'
    '--report-path', $ReportPath
    '--no-banner'
)

if ($StagedOnly) {
    $gitleaksArgs += '--staged'
}

Write-Host "Running gitleaks scan..." -ForegroundColor Cyan

# Run gitleaks
$process = Start-Process -FilePath $gitleaksExe -ArgumentList $gitleaksArgs -Wait -PassThru -NoNewWindow
$exitCode = $process.ExitCode

if ($exitCode -eq 0) {
    Write-Host "✅ Gitleaks: No additional secrets detected" -ForegroundColor Green
    if (Test-Path $ReportPath) { Remove-Item $ReportPath -Force }
    exit 0
}

# Parse and display findings
if (Test-Path $ReportPath) {
    $findings = Get-Content $ReportPath -Raw | ConvertFrom-Json

    Write-Host "" -ForegroundColor Red
    Write-Host "❌ Gitleaks found $($findings.Count) potential secret(s):" -ForegroundColor Red
    Write-Host ("-" * 50) -ForegroundColor DarkGray

    foreach ($finding in $findings) {
        Write-Host "  Rule:    $($finding.RuleID)" -ForegroundColor Yellow
        Write-Host "  File:    $($finding.File):$($finding.StartLine)" -ForegroundColor White
        Write-Host "  Commit:  $($finding.Commit)" -ForegroundColor DarkGray
        Write-Host ""
    }

    # Clean up report (contains secret locations)
    Remove-Item $ReportPath -Force
}

exit $exitCode
#endregion
