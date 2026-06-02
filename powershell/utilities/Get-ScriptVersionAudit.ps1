<#
.SYNOPSIS
    Audits versioning compliance across all PowerShell scripts in the repository.

.DESCRIPTION
    Scans all .ps1 files under powershell/ and reports on version and changelog
    presence, format, and compliance with constitution quality-007/008/009 rules.
    Outputs structured objects for pipeline consumption and optional summary report.

    Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
    MIT License
    Copyright (c) Microsoft Corporation. All rights reserved.

.NOTES
    File Name  : Get-ScriptVersionAudit.ps1
    Author     : GitHubCopilot
    Requires   : PowerShell 5.1
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.0.0
    Changelog  : 1.0.0 - Initial release

.PARAMETER Path
    Root path to scan for .ps1 files. Defaults to powershell/ relative to repo root.

.PARAMETER IncludeTests
    Include test files in the audit. Off by default.

.PARAMETER Summary
    Show a summary table grouped by compliance status.

.EXAMPLE
    .\Get-ScriptVersionAudit.ps1
    Scans all scripts and outputs audit results as objects.

.EXAMPLE
    .\Get-ScriptVersionAudit.ps1 -Summary
    Shows a summary report with counts by status.

.EXAMPLE
    .\Get-ScriptVersionAudit.ps1 | Where-Object Status -ne 'Compliant' | Format-Table
    Lists only non-compliant scripts.

.LINK
    https://github.com/jagilber-dev/scripts
#>

[CmdletBinding()]
param(
    [string]$Path,
    [switch]$IncludeTests,
    [switch]$Summary
)

$ErrorActionPreference = 'Continue'

function main() {
    if (-not $Path) {
        $repoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
        $Path = Join-Path $repoRoot 'powershell'
    }

    if (-not (Test-Path $Path)) {
        Write-Error "Path not found: $Path"
        return
    }

    $scripts = Get-ChildItem -Path $Path -Filter '*.ps1' -Recurse
    if (-not $IncludeTests) {
        $scripts = $scripts | Where-Object { $_.Name -notmatch '\.Tests\.ps1$' }
    }

    $results = @()
    foreach ($script in $scripts) {
        $results += Get-ScriptVersionInfo -FilePath $script.FullName
    }

    if ($Summary) {
        Write-Host "`n=== Script Versioning Audit Summary ===" -ForegroundColor Cyan
        Write-Host "Total scripts scanned: $($results.Count)"
        Write-Host ""

        $grouped = $results | Group-Object Status
        foreach ($group in $grouped | Sort-Object Name) {
            $color = switch ($group.Name) {
                'Compliant' { 'Green' }
                'MissingVersion' { 'Red' }
                'MissingChangelog' { 'Yellow' }
                'NonSemantic' { 'Yellow' }
                'MissingNotes' { 'Red' }
                default { 'White' }
            }
            Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "=== By Category ===" -ForegroundColor Cyan
        $byCategory = $results | Group-Object Category
        foreach ($cat in $byCategory | Sort-Object Name) {
            $compliant = ($cat.Group | Where-Object Status -eq 'Compliant').Count
            Write-Host "  $($cat.Name): $compliant/$($cat.Count) compliant" -ForegroundColor $(if ($compliant -eq $cat.Count) { 'Green' } else { 'Yellow' })
        }
        Write-Host ""
    }

    Write-Output $results
}

function Get-ScriptVersionInfo {
    [CmdletBinding()]
    param(
        [string]$FilePath
    )

    $repoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
    $relativePath = $FilePath.Replace($repoRoot, '').TrimStart('\', '/')
    $category = ($relativePath -split '[/\\]')[1]  # powershell/<category>/...
    $content = Get-Content -Path $FilePath -Raw

    $result = [PSCustomObject]@{
        ScriptName    = [System.IO.Path]::GetFileName($FilePath)
        RelativePath  = $relativePath
        Category      = $category
        HasNotes      = $false
        HasVersion    = $false
        VersionValue  = ''
        VersionFormat = 'None'
        HasChangelog  = $false
        ChangelogText = ''
        Status        = 'Unknown'
        Issues        = @()
    }

    # Check for .NOTES section
    if ($content -match '(?sim)\.NOTES\s*\r?\n(.*?)(?=^\s*\.\w+|\s*\#\>)') {
        $result.HasNotes = $true
        $notesBlock = $Matches[1]

        # Check for Version field (case-insensitive, flexible spacing)
        if ($notesBlock -match '(?im)^\s*Version\s*:\s*(.+)$') {
            $versionValue = $Matches[1].Trim()
            if ($versionValue) {
                $result.HasVersion = $true
                $result.VersionValue = $versionValue

                # Classify format — check date formats before partial semantic
                if ($versionValue -match '^\d+\.\d+\.\d+$') {
                    $result.VersionFormat = 'Semantic'
                }
                elseif ($versionValue -match '^\d{6}\.\d+$') {
                    $result.VersionFormat = 'DateMicro'
                }
                elseif ($versionValue -match '^\d{6}') {
                    $result.VersionFormat = 'DateBased'
                }
                elseif ($versionValue -match '^\d{2}/\d{2}/\d{2}') {
                    $result.VersionFormat = 'DateSlash'
                }
                elseif ($versionValue -match '^\d+\.\d+$') {
                    $result.VersionFormat = 'Semantic-Partial'
                }
                else {
                    $result.VersionFormat = 'Other'
                }
            }
        }

        # Check for Changelog or History field
        if ($notesBlock -match '(?im)^\s*(Changelog|History)\s*:\s*(.+)$') {
            $changelogValue = $Matches[2].Trim()
            if ($changelogValue) {
                $result.HasChangelog = $true
                $result.ChangelogText = $changelogValue
            }
        }
    }

    # Determine compliance status and issues
    $issues = [System.Collections.Generic.List[string]]::new()

    if (-not $result.HasNotes) {
        $issues.Add('Missing .NOTES section')
        $result.Status = 'MissingNotes'
    }
    elseif (-not $result.HasVersion) {
        $issues.Add('Missing Version field in .NOTES')
        $result.Status = 'MissingVersion'
    }
    elseif ($result.VersionFormat -notin @('Semantic', 'Semantic-Partial')) {
        $issues.Add("Non-semantic version format: $($result.VersionFormat) ($($result.VersionValue))")
        $result.Status = 'NonSemantic'
    }
    elseif (-not $result.HasChangelog) {
        $issues.Add('Missing Changelog in .NOTES')
        $result.Status = 'MissingChangelog'
    }
    else {
        $result.Status = 'Compliant'
    }

    $result.Issues = $issues
    return $result
}

main
