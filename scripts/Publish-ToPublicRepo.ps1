<#
.SYNOPSIS
    Publishes the jagilber-dev/scripts dev repo to a private review repo or the public mirror.

.DESCRIPTION
    Copies the repository to a temporary directory, strips private paths listed in
    .publish-exclude, and prepares clean content for publishing.

    By default, copies the cleaned content to a local directory specified via -LocalPath
    for manual review and git operations. Use -CreateReviewRepo to create a private
    GitHub review repo, or -DirectPublish to force-push directly to the public mirror.

    The GitHub CLI (gh) is required only for -CreateReviewRepo.

.PARAMETER Tag
    Git tag to apply to the published commit (e.g., 'v1.0.0').

.PARAMETER DryRun
    When specified, performs all steps except the final git push.

.PARAMETER Force
    When specified, skips confirmation prompts.

.PARAMETER DirectPublish
    Bypass private review repo and force-push directly to the public mirror.

.PARAMETER CreateReviewRepo
    Create a private review repo (jagilber-org/scripts-review-<timestamp>) on GitHub.

.PARAMETER LocalPath
    Local directory to copy cleaned content to. Required for local copy mode (no default).

.PARAMETER RemoteUrl
    URL of the public mirror remote. Defaults to jagilber-org/scripts.

.EXAMPLE
    .\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0' -DryRun
    # Dry run — creates nothing, shows what would happen.

.EXAMPLE
    .\Publish-ToPublicRepo.ps1 -LocalPath 'D:\review\scripts'
    # Copies cleaned content to the specified local directory for review.

.EXAMPLE
    .\Publish-ToPublicRepo.ps1 -CreateReviewRepo
    # Creates a private review repo on GitHub for inspection.

.EXAMPLE
    .\Publish-ToPublicRepo.ps1 -DirectPublish -Force
    # Force-pushes directly to the public mirror without review.

.NOTES

    File Name  : Publish-ToPublicRepo.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.1.0

    Changelog  : 1.1.0 - Default to local copy instead of remote push
                 1.0.0 - Version normalization (constitution quality-007/008/009)

    NOTE: A second copy exists at powershell/automation/Publish-ToPublicRepo.ps1 (canonical).
          Changes should be applied to both files to prevent drift.

#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Tag,

    [switch]$DryRun,

    [switch]$Force,

    [switch]$DirectPublish,

    [switch]$CreateReviewRepo,

    [string]$LocalPath,

    [string]$RemoteUrl = 'https://github.com/jagilber-org/scripts.git'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# Read .publish-exclude
$excludeFile = Join-Path $repoRoot '.publish-exclude'
if (-not (Test-Path $excludeFile)) {
    Write-Error ".publish-exclude not found at $excludeFile"
    return
}

$excludePatterns = Get-Content $excludeFile |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }

Write-Host "Exclusion patterns: $($excludePatterns -join ', ')"

# Create temp directory
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "publish-scripts-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "Copying repo to $tempDir ..."

# Copy repo to temp (exclude .git)
$robocopyArgs = @($repoRoot, $tempDir, '/MIR', '/XD', '.git')
& robocopy @robocopyArgs | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "Robocopy failed with exit code $LASTEXITCODE while copying repo to temp directory"
    return
}

# Remove excluded paths
foreach ($pattern in $excludePatterns) {
    $targetPath = Join-Path $tempDir $pattern
    if (Test-Path $targetPath) {
        Remove-Item $targetPath -Recurse -Force
        Write-Host "Removed excluded: $pattern"
    }
}

# Remove ALL dotfiles and dotfolders (except .git which is already excluded by robocopy)
$dotItems = Get-ChildItem -Path $tempDir -Force | Where-Object { $_.Name.StartsWith('.') }
foreach ($item in $dotItems) {
    Remove-Item $item.FullName -Recurse -Force
    Write-Host "Removed dotfile/dotfolder: $($item.Name)"
}

# Verify no leaked/forbidden artifacts remain
$forbiddenPaths = @(
    '.specify', '.github', '.env', '.env.example', '.pii-allowlist',
    '.secrets.baseline', '.pre-commit-config.yaml', '.private',
    '.certs', 'specs', 'state', 'logs', 'memory', 'hooks',
    'test-results', 'coverage'
)
$leaked = @()
foreach ($forbidden in $forbiddenPaths) {
    $checkPath = Join-Path $tempDir $forbidden
    if (Test-Path $checkPath) {
        $leaked += $forbidden
    }
}

# Also fail if ANY dotfile/dotfolder still exists
$remainingDots = Get-ChildItem -Path $tempDir -Force | Where-Object { $_.Name.StartsWith('.') }
if ($remainingDots) {
    $leaked += $remainingDots.Name
}

if ($leaked.Count -gt 0) {
    Write-Error "Leaked forbidden artifacts detected: $($leaked -join ', '). Aborting."
    Remove-Item $tempDir -Recurse -Force
    return
}

Write-Host "Verify complete: no leaked artifacts or dotfiles found."

# Run PII scan on staged content
$piiScript = Join-Path $repoRoot 'hooks' 'check-pii.ps1'
if (Test-Path $piiScript) {
    Write-Host 'Running PII scan on staged content...'
    $stagedFiles = Get-ChildItem -Path $tempDir -Recurse -File | Where-Object {
        $_.Extension -in '.ps1', '.md', '.json', '.yml', '.yaml', '.txt', '.xml', '.csv'
    } | Select-Object -ExpandProperty FullName
    if ($stagedFiles) {
        $piiResult = & $piiScript -Files $stagedFiles 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "PII scan FAILED. Fix flagged content before publishing.`n$($piiResult | Out-String)"
            Remove-Item $tempDir -Recurse -Force
            return
        }
        Write-Host 'PII scan passed.' -ForegroundColor Green
    }
}
else {
    Write-Warning 'PII scan script not found at hooks/check-pii.ps1 — skipping.'
}

if ($DryRun) {
    if ($DirectPublish) {
        Write-Host "[DRY RUN] Would force-push directly to $RemoteUrl"
    }
    elseif ($CreateReviewRepo) {
        Write-Host "[DRY RUN] Would create private review repo for inspection."
    }
    else {
        Write-Host "[DRY RUN] Would copy cleaned content to $LocalPath"
    }
    Write-Host "[DRY RUN] Temp directory preserved at: $tempDir"
    return
}

if ($DirectPublish -or $CreateReviewRepo) {
    # Initialize git and commit for remote push
    Push-Location $tempDir
    try {
        & git init | Out-Null
        # Use GitHub noreply identity to prevent internal email leakage in public mirror
        & git config user.name 'jagilber' | Out-Null
        & git config user.email 'jagilber@users.noreply.github.com' | Out-Null
        & git add -A | Out-Null
        $commitMsg = "Publish from jagilber-dev/scripts"
        if ($Tag) { $commitMsg += " ($Tag)" }
        & git commit -m $commitMsg | Out-Null

        if ($Tag) {
            & git tag $Tag
        }

        if ($DirectPublish) {
            # Push directly to public mirror
            if (-not $Force) {
                $confirm = Read-Host "Push DIRECTLY to public mirror at $RemoteUrl? (y/N)"
                if ($confirm -ne 'y') {
                    Write-Host "Aborted."
                    return
                }
            }
            & git remote add public $RemoteUrl
            & git push public HEAD:main --force
            Write-Host "Published directly to $RemoteUrl" -ForegroundColor Green
        }
        else {
            # Create a private review repo
            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $reviewRepoName = "scripts-review-$timestamp"
            $reviewOrg = 'jagilber-org'

            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
                Write-Error "GitHub CLI (gh) is required to create private review repos. Install from https://cli.github.com or use -DirectPublish."
                return
            }

            if (-not $Force) {
                $confirm = Read-Host "Create private review repo '$reviewOrg/$reviewRepoName'? (y/N)"
                if ($confirm -ne 'y') {
                    Write-Host "Aborted."
                    return
                }
            }

            & gh repo create "$reviewOrg/$reviewRepoName" --private --confirm 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create private review repo '$reviewOrg/$reviewRepoName'. Verify gh auth status."
                return
            }

            $reviewUrl = "https://github.com/$reviewOrg/$reviewRepoName.git"
            & git remote add review $reviewUrl
            & git push review HEAD:main

            Write-Host ''
            Write-Host '============================================================' -ForegroundColor Cyan
            Write-Host ' PRIVATE REVIEW REPO CREATED' -ForegroundColor Cyan
            Write-Host '============================================================' -ForegroundColor Cyan
            Write-Host "  Repo : https://github.com/$reviewOrg/$reviewRepoName" -ForegroundColor Yellow
            Write-Host "  Scope: Private — only org members can view." -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  Review the content, then either:' -ForegroundColor White
            Write-Host "    1. Run:  .\Publish-ToPublicRepo.ps1 -DirectPublish -Force" -ForegroundColor White
            Write-Host '       to push clean content to the public mirror.' -ForegroundColor White
            Write-Host "    2. Delete the review repo:  gh repo delete $reviewOrg/$reviewRepoName --yes" -ForegroundColor White
            Write-Host '============================================================' -ForegroundColor Cyan
            Write-Host ''
        }
    }
    finally {
        Pop-Location
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    # Default: copy cleaned content to local directory
    if (-not $LocalPath) {
        Write-Error "-LocalPath is required for local copy mode. Specify the target directory."
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    try {
        if (-not (Test-Path $LocalPath)) {
            New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
            Write-Host "Created local target directory: $LocalPath"
        }

        # Mirror cleaned content, preserving any existing .git folder
        $robocopyLocalArgs = @($tempDir, $LocalPath, '/MIR', '/XD', '.git')
        & robocopy @robocopyLocalArgs | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Error "Robocopy failed with exit code $LASTEXITCODE while copying to $LocalPath"
            return
        }

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ' LOCAL COPY COMPLETE' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host "  Path : $LocalPath" -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Review the content, then:' -ForegroundColor White
        Write-Host "    cd $LocalPath" -ForegroundColor White
        Write-Host '    git add -A' -ForegroundColor White
        Write-Host '    git commit -m "Update from dev repo"' -ForegroundColor White
        Write-Host '    git push' -ForegroundColor White
        Write-Host ''
        Write-Host '  Or use -DirectPublish to push directly to the remote.' -ForegroundColor White
        Write-Host '  Or use -CreateReviewRepo to create a private review repo.' -ForegroundColor White
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ''
    }
    finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
