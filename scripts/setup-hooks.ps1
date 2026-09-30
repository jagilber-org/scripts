<#
.SYNOPSIS
    Install and optionally validate the repository hook model.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'This interactive setup command uses color-coded operator status output.'
)]
param(
    [switch]$Validate
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$adoptionPath = Join-Path $repoRoot '.template-adoption.json'
$templateVersion = $null

if (Test-Path $adoptionPath) {
    try {
        $adoption = Get-Content -Raw -Path $adoptionPath | ConvertFrom-Json
        $templateVersion = $adoption.templateVersion
    }
    catch {
        Write-Host 'Warning: .template-adoption.json could not be parsed.' -ForegroundColor Yellow
    }
}

$preCommit = Get-Command pre-commit -ErrorAction SilentlyContinue
if (-not $preCommit) {
    Write-Host 'pre-commit is not installed.' -ForegroundColor Red
    Write-Host 'Install with: pip install pre-commit detect-secrets' -ForegroundColor Yellow
    exit 1
}

$ggshield = Get-Command ggshield -ErrorAction SilentlyContinue
if ($ggshield) {
    Write-Host 'ggshield CLI detected; scans are required when authentication and API quota are available.' -ForegroundColor DarkGray
}
else {
    Write-Host 'ggshield CLI not detected; local secret scanners remain active.' -ForegroundColor Yellow
}

if ($templateVersion) {
    Write-Host ("Adopted template version: {0}" -f $templateVersion) -ForegroundColor DarkGray
}

Write-Host 'Installing pre-commit and pre-push hooks...' -ForegroundColor Cyan
pre-commit install --install-hooks --hook-type pre-commit --hook-type pre-push
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($Validate) {
    Write-Host 'Running pre-commit validation across the working tree...' -ForegroundColor Cyan
    pre-commit run --all-files
    exit $LASTEXITCODE
}

Write-Host 'Hook installation complete.' -ForegroundColor Green
