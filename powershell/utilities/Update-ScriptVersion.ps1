<#
.SYNOPSIS
    Normalizes versioning across all PowerShell scripts to semantic versioning format.

.DESCRIPTION
    Scans scripts under powershell/ and ensures each has a compliant .NOTES section
    with semantic Version (Major.Minor.Patch) and Changelog fields per constitution
    quality-007/008/009 rules.

    Actions performed:
    - Adds .NOTES section if missing
    - Adds Version field if missing (defaults to 1.0.0)
    - Converts date-based versions (YYMMDD) to 1.0.0 with original date in changelog
    - Converts partial semantic (1.1) to full semantic (1.1.0)
    - Adds Changelog field if missing
    - Supports -WhatIf for dry-run preview

    Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
    MIT License
    Copyright (c) Microsoft Corporation. All rights reserved.

.NOTES
    File Name  : Update-ScriptVersion.ps1
    Author     : GitHubCopilot
    Requires   : PowerShell 5.1
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.0.0
    Changelog  : 1.0.0 - Initial release

.PARAMETER Path
    Root path to scan for .ps1 files. Defaults to powershell/ relative to repo root.

.PARAMETER DefaultVersion
    Version to assign to scripts with no version or non-semantic versions. Defaults to 1.0.0.

.PARAMETER IncludeTests
    Include test files in normalization. Off by default.

.EXAMPLE
    .\Update-ScriptVersion.ps1 -WhatIf
    Preview all changes without modifying files.

.EXAMPLE
    .\Update-ScriptVersion.ps1
    Apply versioning normalization to all scripts.

.EXAMPLE
    .\Update-ScriptVersion.ps1 -Path .\powershell\azure
    Normalize only azure category scripts.

.LINK
    https://github.com/jagilber-dev/scripts
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path,
    [string]$DefaultVersion = '1.0.0',
    [switch]$IncludeTests
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

    $stats = @{
        Scanned         = 0
        AlreadyCompliant = 0
        AddedNotes      = 0
        AddedVersion    = 0
        ConvertedDate   = 0
        ConvertedPartial = 0
        AddedChangelog  = 0
        Errors          = 0
    }

    foreach ($script in $scripts) {
        $stats.Scanned++
        try {
            Update-ScriptVersionInfo -FilePath $script.FullName -Stats ([ref]$stats)
        }
        catch {
            $stats.Errors++
            Write-Warning "Error processing $($script.Name): $_"
        }
    }

    Write-Host "`n=== Normalization Summary ===" -ForegroundColor Cyan
    Write-Host "  Scanned:            $($stats.Scanned)"
    Write-Host "  Already compliant:  $($stats.AlreadyCompliant)" -ForegroundColor Green
    Write-Host "  Added .NOTES:       $($stats.AddedNotes)" -ForegroundColor Yellow
    Write-Host "  Added Version:      $($stats.AddedVersion)" -ForegroundColor Yellow
    Write-Host "  Converted date:     $($stats.ConvertedDate)" -ForegroundColor Yellow
    Write-Host "  Converted partial:  $($stats.ConvertedPartial)" -ForegroundColor Yellow
    Write-Host "  Added Changelog:    $($stats.AddedChangelog)" -ForegroundColor Yellow
    Write-Host "  Errors:             $($stats.Errors)" -ForegroundColor $(if ($stats.Errors -gt 0) { 'Red' } else { 'Green' })
}

function Update-ScriptVersionInfo {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$FilePath,
        [ref]$Stats
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $content = Get-Content -Path $FilePath -Raw
    $originalContent = $content
    $changed = $false

    # === CASE 1: No .NOTES section at all ===
    if ($content -notmatch '(?si)\.NOTES') {
        # Find insertion point: before first .PARAMETER, .EXAMPLE, .LINK, or #>
        $insertPattern = '(?m)^(\s*)\.(PARAMETER|EXAMPLE|LINK)\b'
        $closePattern = '(?m)^(\s*)#>'

        $notesBlock = @"

.NOTES
    File Name  : $fileName
    Author     : jagilber
    Disclaimer : Provided AS-IS without warranty.
    Version    : $DefaultVersion
    Changelog  : $DefaultVersion - Version normalization (constitution quality-007/008/009)

"@

        if ($content -match $insertPattern) {
            $insertMatch = [regex]::Match($content, $insertPattern)
            $indent = $insertMatch.Groups[1].Value
            $notesBlock = "$indent.NOTES`r`n${indent}    File Name  : $fileName`r`n${indent}    Author     : jagilber`r`n${indent}    Disclaimer : Provided AS-IS without warranty.`r`n${indent}    Version    : $DefaultVersion`r`n${indent}    Changelog  : $DefaultVersion - Version normalization (constitution quality-007/008/009)`r`n`r`n$indent"
            $content = $content.Substring(0, $insertMatch.Index) + $notesBlock + $content.Substring($insertMatch.Index)
            $changed = $true
            $Stats.Value.AddedNotes++
            $Stats.Value.AddedVersion++
            $Stats.Value.AddedChangelog++
            Write-Verbose "[$fileName] Added .NOTES section with version $DefaultVersion"
        }
        elseif ($content -match $closePattern) {
            $closeMatch = [regex]::Match($content, $closePattern)
            $indent = $closeMatch.Groups[1].Value
            $notesBlock = "`r`n${indent}.NOTES`r`n${indent}    File Name  : $fileName`r`n${indent}    Author     : jagilber`r`n${indent}    Disclaimer : Provided AS-IS without warranty.`r`n${indent}    Version    : $DefaultVersion`r`n${indent}    Changelog  : $DefaultVersion - Version normalization (constitution quality-007/008/009)`r`n`r`n"
            $content = $content.Substring(0, $closeMatch.Index) + $notesBlock + $content.Substring($closeMatch.Index)
            $changed = $true
            $Stats.Value.AddedNotes++
            $Stats.Value.AddedVersion++
            $Stats.Value.AddedChangelog++
            Write-Verbose "[$fileName] Added .NOTES section before #>"
        }
        else {
            Write-Warning "[$fileName] Could not find insertion point for .NOTES"
            $Stats.Value.Errors++
            return
        }
    }
    else {
        # === .NOTES exists — check Version and Changelog ===
        $notesMatch = [regex]::Match($content, '(?sim)(\.NOTES\s*\r?\n)(.*?)(?=^\s*\.\w+|\s*\#\>)')
        if (-not $notesMatch.Success) {
            Write-Warning "[$fileName] Could not parse .NOTES section"
            $Stats.Value.Errors++
            return
        }

        $notesHeader = $notesMatch.Groups[1].Value
        $notesBody = $notesMatch.Groups[2].Value
        $newNotesBody = $notesBody
        $notesChanged = $false

        # Detect indentation from existing .NOTES lines
        $indentMatch = [regex]::Match($notesBody, '(?m)^(\s+)\w')
        $indent = if ($indentMatch.Success) { $indentMatch.Groups[1].Value } else { '    ' }

        # --- Handle Version field ---
        $versionMatch = [regex]::Match($notesBody, '(?im)^(\s*)(Version\s*:\s*)(.*)$')
        $hasVersion = $versionMatch.Success -and $versionMatch.Groups[3].Value.Trim()
        $versionValue = if ($hasVersion) { $versionMatch.Groups[3].Value.Trim() } else { '' }
        $newVersion = $DefaultVersion

        if ($hasVersion) {
            # Classify and convert — check date formats BEFORE partial semantic
            if ($versionValue -match '^\d+\.\d+\.\d+$') {
                # Already semantic — keep it
                $newVersion = $versionValue
            }
            elseif ($versionValue -match '^\d{6}') {
                # Date-based (YYMMDD) or DateMicro (YYMMDD.N) -> DefaultVersion
                $newVersion = $DefaultVersion
                $Stats.Value.ConvertedDate++
            }
            elseif ($versionValue -match '^\d{2}/\d{2}/\d{2}') {
                # Date slash format
                $newVersion = $DefaultVersion
                $Stats.Value.ConvertedDate++
            }
            elseif ($versionValue -match '^(\d+)\.(\d+)$') {
                # Partial semantic (1.1) -> (1.1.0)
                $newVersion = "$versionValue.0"
                $Stats.Value.ConvertedPartial++
            }
            else {
                # Unknown format -> DefaultVersion
                $newVersion = $DefaultVersion
                $Stats.Value.ConvertedDate++
            }

            if ($newVersion -ne $versionValue) {
                $oldLine = $versionMatch.Value
                $prefix = $versionMatch.Groups[1].Value + $versionMatch.Groups[2].Value
                # Normalize spacing: "Version    : value"
                $prefix = $prefix -replace 'Version\s*:', 'Version    :'
                $newLine = "${prefix}$newVersion"
                $newNotesBody = $newNotesBody.Replace($oldLine, $newLine)
                $notesChanged = $true
                Write-Verbose "[$fileName] Converted version '$versionValue' -> '$newVersion'"
            }
        }
        else {
            # Add Version field
            # Insert after last known field or at end of notes body
            $lastFieldMatch = [regex]::Match($newNotesBody, '(?im)^(\s*)(File Name|Author|Requires|Prerequisite|Disclaimer)\s*:.*$')
            if ($lastFieldMatch.Success) {
                # Find the last field by iterating
                $fieldPattern = '(?im)^(\s*)(File Name|Author|Requires|Prerequisite|Disclaimer|Version|History|Changelog)\s*:.*$'
                $fieldMatches = [regex]::Matches($newNotesBody, $fieldPattern)
                if ($fieldMatches.Count -gt 0) {
                    $lastField = $fieldMatches[$fieldMatches.Count - 1]
                    $insertPos = $lastField.Index + $lastField.Length
                    $versionLine = "`r`n${indent}Version    : $DefaultVersion"
                    $newNotesBody = $newNotesBody.Insert($insertPos, $versionLine)
                    $notesChanged = $true
                    $Stats.Value.AddedVersion++
                    Write-Verbose "[$fileName] Added Version field"
                }
            }
            else {
                # Append to end of notes body
                $versionLine = "${indent}Version    : $DefaultVersion`r`n"
                $newNotesBody = $newNotesBody.TrimEnd() + "`r`n$versionLine"
                $notesChanged = $true
                $Stats.Value.AddedVersion++
                Write-Verbose "[$fileName] Appended Version field"
            }
        }

        # --- Handle Changelog/History field ---
        $changelogMatch = [regex]::Match($newNotesBody, '(?im)^(\s*)(Changelog|History)\s*:\s*(.*)$')
        $hasChangelog = $changelogMatch.Success -and $changelogMatch.Groups[3].Value.Trim()

        if (-not $hasChangelog) {
            $changelogEntry = if ($hasVersion -and $versionValue -ne $newVersion) {
                "$newVersion - Version normalization from $versionValue (constitution quality-007/008/009)"
            }
            else {
                "$newVersion - Version normalization (constitution quality-007/008/009)"
            }

            if ($changelogMatch.Success) {
                # History/Changelog field exists but empty — replace it
                $oldLine = $changelogMatch.Value
                $prefix = $changelogMatch.Groups[1].Value
                $newLine = "${prefix}Changelog  : $changelogEntry"
                $newNotesBody = $newNotesBody.Replace($oldLine, $newLine)
                $notesChanged = $true
            }
            else {
                # No Changelog/History field — add after Version line
                $versionLineMatch = [regex]::Match($newNotesBody, '(?im)^(\s*)Version\s*:.*$')
                if ($versionLineMatch.Success) {
                    $insertPos = $versionLineMatch.Index + $versionLineMatch.Length
                    $changelogLine = "`r`n${indent}Changelog  : $changelogEntry"
                    $newNotesBody = $newNotesBody.Insert($insertPos, $changelogLine)
                    $notesChanged = $true
                }
            }
            $Stats.Value.AddedChangelog++
            Write-Verbose "[$fileName] Added Changelog entry"
        }

        if ($notesChanged) {
            $content = $content.Substring(0, $notesMatch.Groups[2].Index) + $newNotesBody + $content.Substring($notesMatch.Groups[2].Index + $notesMatch.Groups[2].Length)
            $changed = $true
        }
    }

    if (-not $changed) {
        $Stats.Value.AlreadyCompliant++
        Write-Verbose "[$fileName] Already compliant"
        return
    }

    if ($PSCmdlet.ShouldProcess($FilePath, "Update version and changelog")) {
        Set-Content -Path $FilePath -Value $content -NoNewline -Encoding UTF8
        Write-Host "  Updated: $fileName" -ForegroundColor Green
    }
    else {
        Write-Host "  Would update: $fileName" -ForegroundColor Yellow
    }
}

main
