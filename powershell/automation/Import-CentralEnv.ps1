<#
.SYNOPSIS
    Load central environment variables from C:\github\.env into current session.

.DESCRIPTION
    Reads the central .env file at C:\github\.env and sets environment variables
    for the current PowerShell session. This provides a single source of truth
    for shared credentials and configuration across all repos.

    Skips commented lines, blank lines, and empty values.
    Does not override existing environment variables unless -Force is specified.

    Designed to be called from $PROFILE for automatic loading on shell startup.

.PARAMETER Path
    Path to the central .env file. Defaults to C:\github\.env.

.PARAMETER Force
    Override existing environment variables with values from .env file.

.PARAMETER Quiet
    Suppress output (useful when called from $PROFILE).

.EXAMPLE
    Import-CentralEnv

    Loads variables from C:\github\.env into the current session.

.EXAMPLE
    Import-CentralEnv -Force

    Loads variables, overwriting any existing env vars.

.EXAMPLE
    Import-CentralEnv -Quiet

    Loads variables silently (for $PROFILE use).

.EXAMPLE
    . C:\github\jagilber-dev\scripts\powershell\automation\Import-CentralEnv.ps1

    Dot-source to load variables into calling scope.

.NOTES
    Author: jagilber
    Version    : 1.0.0
    Changelog  : 1.0.0 - Version normalization from 1.0 (constitution quality-007/008/009)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$Quiet
)

if (-not $Path) {
    $Path = 'C:\github\.env'
    Write-Warning "Import-CentralEnv: -Path not specified, defaulting to '$Path'. This default will be removed in a future version. Please pass -Path explicitly."
}

function Import-CentralEnv {
    [CmdletBinding()]
    param(
        [string]$EnvFilePath,
        [bool]$OverrideExisting,
        [bool]$SuppressOutput
    )

    if (-not (Test-Path $EnvFilePath)) {
        if (-not $SuppressOutput) {
            Write-Warning "Central .env file not found: $EnvFilePath"
        }
        return
    }

    $loadedCount = 0
    $skippedCount = 0

    foreach ($line in (Get-Content $EnvFilePath)) {
        $trimmed = $line.Trim()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        # Parse KEY=VALUE
        if ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)=(.+)$') {
            $key = $matches[1]
            $value = $matches[2].Trim()

            # Remove surrounding quotes
            if ($value -match '^["''](.*)["`'']$') {
                $value = $matches[1]
            }

            # Skip if already set and not forcing
            $existing = [System.Environment]::GetEnvironmentVariable($key, 'Process')
            if ($existing -and -not $OverrideExisting) {
                $skippedCount++
                continue
            }

            [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            $loadedCount++
        }
    }

    if (-not $SuppressOutput) {
        Write-Host "Central .env: loaded $loadedCount var(s)" -ForegroundColor Green
        if ($skippedCount -gt 0) {
            Write-Host "  Skipped $skippedCount existing var(s) (use -Force to override)" -ForegroundColor Yellow
        }
    }
}

Import-CentralEnv -EnvFilePath $Path -OverrideExisting $Force.IsPresent -SuppressOutput $Quiet.IsPresent
