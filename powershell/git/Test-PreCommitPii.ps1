<#
.SYNOPSIS
    Pre-commit hook scanner that blocks PII, secrets, and sensitive Azure patterns.

.DESCRIPTION
    Three-layer scanning for staged git commits:
      Layer 1: Block forbidden file types (.env, .key, .pem, .pfx, etc.)
      Layer 2: Scan staged diffs for actual values loaded from a central .env file
      Layer 3: Regex patterns for generic PII and Azure credential patterns

    The central .env file is located by walking up from the repo root looking for
    a .env file outside any git repository. Override with -EnvFilePath.

.NOTES

    File Name  : Test-PreCommitPii.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.PARAMETER DryRun
    Report findings without blocking the commit (exit 0 regardless).

.PARAMETER EnvFilePath
    Explicit path to the central .env file. If omitted, searches parent directories.

.PARAMETER MinValueLength
    Minimum character length for .env values to be checked (avoids false positives). Default: 8.

.PARAMETER Verbose
    Show detailed output during scanning.

.EXAMPLE
    .\Test-PreCommitPii.ps1
    # Normal pre-commit hook execution

.EXAMPLE
    .\Test-PreCommitPii.ps1 -DryRun
    # Report only, do not block

.EXAMPLE
    .\Test-PreCommitPii.ps1 -DryRun -Verbose
    # Detailed report for testing
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$EnvFilePath,
    [int]$MinValueLength = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Output Helpers
function Write-Status {
    param([string]$Message, [string]$Color = 'White')
    Write-Host $Message -ForegroundColor $Color
}

function Write-Block {
    param([string]$File, [string]$Reason)
    Write-Status "  BLOCKED: $File" -Color Red
    Write-Status "    Reason: $Reason" -Color Yellow
    $script:blockCount++
}

function Write-Warn {
    param([string]$File, [string]$Reason)
    Write-Status "  WARNING: $File" -Color Yellow
    Write-Status "    Reason: $Reason" -Color DarkYellow
    $script:warnCount++
}
#endregion

#region Central .env Discovery
function Find-CentralEnvFile {
    <#
    .SYNOPSIS
        Walk up from repo root to find .env file outside any git repo.
    #>
    if ($EnvFilePath -and (Test-Path $EnvFilePath)) {
        return $EnvFilePath
    }

    # Start from repo root, walk up
    $dir = git rev-parse --show-toplevel 2>$null
    if (-not $dir) { $dir = (Get-Location).Path }

    # Normalize to parent of repo
    $dir = Split-Path $dir -Parent

    for ($i = 0; $i -lt 5; $i++) {
        if (-not $dir -or $dir -eq [System.IO.Path]::GetPathRoot($dir)) { break }
        $candidate = Join-Path $dir '.env'
        $candidateGit = Join-Path $dir '.git'

        # We want a .env that is NOT inside a git repo
        if ((Test-Path $candidate) -and -not (Test-Path $candidateGit)) {
            Write-Verbose "Found central .env: $candidate"
            return $candidate
        }
        $dir = Split-Path $dir -Parent
    }

    Write-Verbose "No central .env file found"
    return $null
}
#endregion

#region Layer 1: Forbidden File Patterns
function Test-ForbiddenFiles {
    param([string[]]$StagedFiles)

    Write-Status "Layer 1: Checking for forbidden file types..." -Color Cyan

    $forbiddenPatterns = @(
        @{ Pattern = '(^|/)\.env$';                   Reason = '.env file (secrets)' }
        @{ Pattern = '(^|/)\.env\.[^e]';              Reason = '.env.* file (secrets)' }
        @{ Pattern = '(^|/)\.env\.local$';             Reason = '.env.local file (secrets)' }
        @{ Pattern = '\.key$';                         Reason = 'Private key file' }
        @{ Pattern = '\.pem$';                         Reason = 'PEM certificate/key file' }
        @{ Pattern = '\.pfx$';                         Reason = 'PFX certificate file' }
        @{ Pattern = '\.p12$';                         Reason = 'P12 certificate file' }
        @{ Pattern = '\.jks$';                         Reason = 'Java keystore file' }
        @{ Pattern = '\.keystore$';                    Reason = 'Keystore file' }
        @{ Pattern = '\.secret$';                      Reason = 'Secret file' }
        @{ Pattern = '\.pii$';                         Reason = 'PII data file' }
        @{ Pattern = '\.sensitive$';                   Reason = 'Sensitive data file' }
        @{ Pattern = '\.credentials$';                 Reason = 'Credentials file' }
        @{ Pattern = '(^|/)id_rsa';                    Reason = 'SSH private key' }
        @{ Pattern = '(^|/)id_ed25519';                Reason = 'SSH private key' }
        @{ Pattern = '(^|/)\.htpasswd$';               Reason = 'Password file' }
        @{ Pattern = '(^|/)\.netrc$';                  Reason = 'Network credentials file' }
        @{ Pattern = '(^|/)\.npmrc$';                  Reason = 'NPM config (may contain tokens)' }
        @{ Pattern = '(^|/)\.pypirc$';                 Reason = 'PyPI credentials file' }
        @{ Pattern = '(^|/)secrets\.';                 Reason = 'Secrets file' }
        @{ Pattern = '(^|/)credentials\.';             Reason = 'Credentials file' }
    )

    # Allow .env.example explicitly
    $allowPatterns = @('\.env\.example$', '\.env\.sample$', '\.env\.template$')

    $blocked = $false
    foreach ($file in $StagedFiles) {
        # Check allow list first
        $allowed = $false
        foreach ($ap in $allowPatterns) {
            if ($file -match $ap) { $allowed = $true; break }
        }
        if ($allowed) { continue }

        foreach ($fp in $forbiddenPatterns) {
            if ($file -match $fp.Pattern) {
                Write-Block -File $file -Reason $fp.Reason
                $blocked = $true
                break
            }
        }
    }

    if (-not $blocked) {
        Write-Status "  OK: No forbidden files in staging" -Color Green
    }
    return (-not $blocked)
}
#endregion

#region Layer 2: Central .env Value Scanning
function Test-EnvValues {
    param([string[]]$StagedFiles)

    Write-Status "Layer 2: Scanning for central .env values in diffs..." -Color Cyan

    $envFile = Find-CentralEnvFile
    if (-not $envFile) {
        Write-Status "  SKIP: No central .env file found" -Color DarkGray
        return $true
    }

    # Parse .env file into key-value pairs
    $sensitiveEntries = @()
    foreach ($line in (Get-Content $envFile -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim() -replace '^["'']+|["'']+$', ''

            # Skip placeholders, short values, and non-sensitive defaults
            if ($value.Length -lt $MinValueLength) { continue }
            if ($value -match '^(your-|my-|example|REPLACE_|<.*>|\$\{.*\}|fake-|true|false|null)') { continue }
            # Skip pure path-like local values (e.g., ./output)
            if ($value -match '^\./[a-z]' -and $value.Length -lt 15) { continue }

            $sensitiveEntries += @{ Key = $key; Value = $value }
        }
    }

    Write-Verbose "Loaded $($sensitiveEntries.Count) sensitive values from central .env"

    if ($sensitiveEntries.Count -eq 0) {
        Write-Status "  SKIP: No sensitive values to check" -Color DarkGray
        return $true
    }

    # Scan staged diffs
    $blocked = $false
    foreach ($file in $StagedFiles) {
        # Skip files that are expected to contain env references
        if ($file -match '\.(example|sample|template)$|\.gitignore$|package-lock\.json$') { continue }

        $diff = git diff --cached -- $file 2>$null
        if (-not $diff) { continue }

        # Only check added lines (lines starting with +)
        $addedLines = ($diff -split "`n") | Where-Object { $_ -match '^\+[^+]' }
        if (-not $addedLines) { continue }
        $addedText = $addedLines -join "`n"

        foreach ($entry in $sensitiveEntries) {
            $escaped = [regex]::Escape($entry.Value)
            if ($addedText -match $escaped) {
                Write-Block -File $file -Reason "Contains value of $($entry.Key) from central .env"
                $blocked = $true
                break  # One match per file is enough
            }
        }
    }

    if (-not $blocked) {
        Write-Status "  OK: No .env values found in staged diffs" -Color Green
    }
    return (-not $blocked)
}
#endregion

#region Layer 3: PII and Azure Credential Pattern Scanning
function Test-PiiPatterns {
    param([string[]]$StagedFiles)

    Write-Status "Layer 3: Scanning for PII and credential patterns..." -Color Cyan

    # Blocking patterns - commit is rejected
    $blockPatterns = @(
        # Secrets and credentials with values
        @{ Pattern = 'BEGIN\s+(RSA|DSA|EC|OPENSSH|PGP)\s+PRIVATE\s+KEY';  Name = 'Private key block' }
        @{ Pattern = 'BEGIN\s+CERTIFICATE';                                Name = 'Certificate block' }

        # Azure-specific high-confidence patterns
        @{ Pattern = 'AccountKey=[A-Za-z0-9+/=]{40,}';                    Name = 'Azure Storage account key' }
        @{ Pattern = 'SharedAccessSignature=sv=[^&\s]{20,}';              Name = 'Azure SAS token' } # pii-allowlist
        @{ Pattern = 'sig=[A-Za-z0-9%+/=]{40,}';                          Name = 'Azure SAS signature' }
        @{ Pattern = 'DefaultEndpointsProtocol=https;AccountName=\w+;AccountKey='; Name = 'Azure Storage connection string' } # pii-allowlist
        @{ Pattern = 'Server=tcp:.*\.database\.windows\.net.*Password=';   Name = 'Azure SQL connection string with password' }
        @{ Pattern = 'Endpoint=sb://.*\.servicebus\.windows\.net.*SharedAccessKey='; Name = 'Azure Service Bus connection string' }
        @{ Pattern = 'HostName=.*\.azure-devices\.net.*SharedAccessKey=';  Name = 'Azure IoT Hub connection string' }
        @{ Pattern = 'InstrumentationKey=[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'; Name = 'Application Insights instrumentation key' }

        # API keys with high-confidence prefixes
        @{ Pattern = 'sk-[A-Za-z0-9]{20,}';                               Name = 'OpenAI/Stripe API key' }
        @{ Pattern = 'ghp_[A-Za-z0-9]{36,}';                              Name = 'GitHub personal access token' }
        @{ Pattern = 'gho_[A-Za-z0-9]{36,}';                              Name = 'GitHub OAuth token' }
        @{ Pattern = 'ghs_[A-Za-z0-9]{36,}';                              Name = 'GitHub server token' }
        @{ Pattern = 'ghu_[A-Za-z0-9]{36,}';                              Name = 'GitHub user token' }
        @{ Pattern = 'github_pat_[A-Za-z0-9_]{20,}';                      Name = 'GitHub fine-grained PAT' }
        @{ Pattern = 'AKIA[0-9A-Z]{16}';                                  Name = 'AWS access key ID' }
        @{ Pattern = 'AIza[0-9A-Za-z\-_]{35}';                            Name = 'Google API key' }
        @{ Pattern = 'xox[bpoas]-[0-9]{10,}';                             Name = 'Slack token' }
        @{ Pattern = 'npm_[A-Za-z0-9]{36,}';                              Name = 'NPM access token' }

        # Base64-encoded certificates/keys (long base64 blobs)
        @{ Pattern = 'MIIK[A-Za-z0-9+/=]{100,}';                          Name = 'Base64-encoded PFX/certificate' }

        # Password assignments with actual values (not placeholders)
        @{ Pattern = '[Pp]assword\s*[=:]\s*[''"]?[^\s''"<$]{8,}';         Name = 'Hardcoded password' }

        # PII patterns
        @{ Pattern = '\b\d{3}-\d{2}-\d{4}\b';                             Name = 'US SSN pattern' }
        @{ Pattern = '\b[0-9]{4}[\s-]?[0-9]{4}[\s-]?[0-9]{4}[\s-]?[0-9]{4}\b'; Name = 'Credit card number pattern' }
    )

    # Warning-only patterns (do not block)
    $warnPatterns = @(
        @{ Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(onmicrosoft|microsoft|outlook)\.com\b'; Name = 'Microsoft email address' }
        @{ Pattern = 'api[_-]?key\s*[=:]\s*[''"]?[A-Za-z0-9\-_]{10,}';    Name = 'Possible API key assignment' }
        @{ Pattern = 'secret\s*[=:]\s*[''"]?[A-Za-z0-9\-_+/=]{10,}';      Name = 'Possible secret assignment' }
        @{ Pattern = 'token\s*[=:]\s*[''"]?[A-Za-z0-9\-_]{10,}';          Name = 'Possible token assignment' }
        @{ Pattern = '[Tt]humbprint\s*[=:]\s*[''"]?[0-9a-fA-F]{40}';      Name = 'Certificate thumbprint' }
    )

    # File types to skip for pattern scanning
    $skipPatterns = @(
        '\.example$', '\.sample$', '\.template$',
        '\.gitignore$', '\.git/', 'node_modules/',
        'package-lock\.json$', 'yarn\.lock$', 'pnpm-lock\.yaml$',
        '\.(png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp4|mp3|zip|gz|tar|bin|exe|dll|so|dylib)$'
    )

    $blocked = $false

    foreach ($file in $StagedFiles) {
        # Skip excluded file types
        $skip = $false
        foreach ($sp in $skipPatterns) {
            if ($file -match $sp) { $skip = $true; break }
        }
        if ($skip) { continue }

        $diff = git diff --cached -- $file 2>$null
        if (-not $diff) { continue }

        # Only check added lines
        $addedLines = ($diff -split "`n") | Where-Object { $_ -match '^\+[^+]' }
        if (-not $addedLines) { continue }
        $addedText = $addedLines -join "`n"

        # Check blocking patterns
        foreach ($bp in $blockPatterns) {
            if ($addedText -match $bp.Pattern) {
                Write-Block -File $file -Reason $bp.Name
                $blocked = $true
                break
            }
        }

        # Check warning patterns
        foreach ($wp in $warnPatterns) {
            if ($addedText -match $wp.Pattern) {
                Write-Warn -File $file -Reason $wp.Name
                break
            }
        }
    }

    if (-not $blocked -and $script:warnCount -eq 0) {
        Write-Status "  OK: No PII or credential patterns detected" -Color Green
    } elseif (-not $blocked) {
        Write-Status "  OK (with warnings): Review warnings above" -Color Yellow
    }

    return (-not $blocked)
}
#endregion

#region Main
$script:blockCount = 0
$script:warnCount = 0

$mode = if ($DryRun) { "DRY RUN" } else { "ENFORCING" }
Write-Status "Pre-commit PII scan [$mode]" -Color Cyan
Write-Status ("-" * 50) -Color DarkGray

# Get staged files
$stagedFiles = @(git diff --cached --name-only --diff-filter=ACM 2>$null)
if ($stagedFiles.Count -eq 0) {
    Write-Status "No staged files to check" -Color Green
    exit 0
}

Write-Status "Scanning $($stagedFiles.Count) staged file(s)..." -Color White

$pass = $true

# Layer 1: Forbidden files
if (-not (Test-ForbiddenFiles -StagedFiles $stagedFiles)) { $pass = $false }

# Layer 2: Central .env values
if (-not (Test-EnvValues -StagedFiles $stagedFiles)) { $pass = $false }

# Layer 3: PII and credential patterns
if (-not (Test-PiiPatterns -StagedFiles $stagedFiles)) { $pass = $false }

# Summary
Write-Status ("-" * 50) -Color DarkGray
if ($pass) {
    Write-Status "PASSED: All pre-commit security checks passed ($($script:warnCount) warning(s))" -Color Green
    exit 0
} else {
    Write-Status "BLOCKED: $($script:blockCount) issue(s) found, $($script:warnCount) warning(s)" -Color Red
    if ($DryRun) {
        Write-Status "DRY RUN: Commit would be blocked (exiting 0 for dry run)" -Color Yellow
        exit 0
    } else {
        Write-Status "Fix issues above or use 'git commit --no-verify' to override" -Color Yellow
        exit 1
    }
}
#endregion
