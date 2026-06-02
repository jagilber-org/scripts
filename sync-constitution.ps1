<#
.SYNOPSIS
    Generates or checks .specify/memory/constitution.md from constitution.json.

.DESCRIPTION
    Reads constitution.json at the repository root and generates a human-readable
    markdown rendering at .specify/memory/constitution.md.
    When -Check is specified, compares the current markdown file against what would
    be generated and exits with code 1 if they differ (drift detection for CI).

.PARAMETER Check
    When specified, compares existing constitution.md against expected output.
    Exits with code 0 if in sync, code 1 if drifted or missing.

.EXAMPLE
    .\sync-constitution.ps1
    # Regenerates .specify/memory/constitution.md

.EXAMPLE
    .\sync-constitution.ps1 -Check
    # Exits 0 if in sync, 1 if drifted (for CI)
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }

$jsonPath = Join-Path $repoRoot 'constitution.json'
$mdPath = Join-Path $repoRoot '.specify\memory\constitution.md'

if (-not (Test-Path $jsonPath)) {
    Write-Error "constitution.json not found at $jsonPath"
    exit 1
}

$constitution = Get-Content $jsonPath -Raw | ConvertFrom-Json

# Build expected markdown content
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Constitution Reference')
[void]$sb.AppendLine()
[void]$sb.AppendLine('> Auto-generated from `constitution.json` by `sync-constitution.ps1`. Do not edit manually.')

foreach ($article in $constitution.articles) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Article: $($article.title)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**ID**: $($article.id)  ")
    [void]$sb.AppendLine("**Description**: $($article.description)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| # | Rule | Severity |')
    [void]$sb.AppendLine('|---|------|----------|')

    $ruleNum = 0
    foreach ($rule in $article.rules) {
        $ruleNum++
        [void]$sb.AppendLine("| $ruleNum | $($rule.text) | $($rule.severity) |")
    }
}

$expected = $sb.ToString().TrimEnd() + "`n"

if ($Check) {
    if (-not (Test-Path $mdPath)) {
        Write-Warning "constitution.md is missing at $mdPath"
        exit 1
    }

    $current = (Get-Content $mdPath -Raw).TrimEnd() + "`n"
    if ($current -ne $expected) {
        Write-Warning "constitution.md is out of sync with constitution.json. Run .\sync-constitution.ps1 to regenerate."
        exit 1
    }

    Write-Host "constitution.md is in sync."
    exit 0
}

# Generate mode
$mdDir = Split-Path $mdPath -Parent
if (-not (Test-Path $mdDir)) {
    New-Item -ItemType Directory -Path $mdDir -Force | Out-Null
}

$expected = $expected.TrimEnd("`r", "`n")
Set-Content -Path $mdPath -Value $expected
Write-Host "Generated $mdPath from constitution.json"
