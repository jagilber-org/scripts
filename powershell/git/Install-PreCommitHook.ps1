<#
.SYNOPSIS
    Deploys the PII-blocking pre-commit hook to one or more git repositories.

.DESCRIPTION
    Copies the shell wrapper (pre-commit) to .git/hooks/ for each target repo
    and ensures .env is listed in .gitignore. Can target a single repo, a list
    of repos, or auto-discover all repos under a parent directory.

.NOTES

    File Name  : Install-PreCommitHook.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.PARAMETER RepoPath
    Path to a single git repository to install the hook into.

.PARAMETER ParentPath
    Path to a parent directory. All immediate child directories containing .git
    will receive the hook.

.PARAMETER RepoPaths
    Array of explicit repo paths.

.PARAMETER Force
    Overwrite existing pre-commit hooks.

.PARAMETER WhatIf
    Show what would be done without making changes.

.PARAMETER SkipGitignore
    Skip adding .env to .gitignore.

.EXAMPLE
    .\Install-PreCommitHook.ps1 -ParentPath C:\github\jagilber
    # Install hook to all repos under jagilber

.EXAMPLE
    .\Install-PreCommitHook.ps1 -RepoPath C:\github\jagilber\mcp-pr -WhatIf
    # Preview installation for a single repo

.EXAMPLE
    .\Install-PreCommitHook.ps1 -ParentPath C:\github\jagilber, C:\github\jagilber-org
    # Install to all repos under both directories
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Parent')]
param(
    [Parameter(ParameterSetName = 'Single')]
    [string]$RepoPath,

    [Parameter(ParameterSetName = 'Parent')]
    [string[]]$ParentPath,

    [Parameter(ParameterSetName = 'Multiple')]
    [string[]]$RepoPaths,

    [switch]$Force,

    [switch]$SkipGitignore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$hookSource = Join-Path $scriptDir 'pre-commit'

if (-not (Test-Path $hookSource)) {
    Write-Error "pre-commit hook template not found at: $hookSource"
    return
}

#region Repo Discovery
function Get-TargetRepos {
    $repos = @()

    switch ($PSCmdlet.ParameterSetName) {
        'Single' {
            if ($RepoPath) { $repos += $RepoPath }
        }
        'Multiple' {
            $repos += $RepoPaths
        }
        'Parent' {
            if (-not $ParentPath) {
                Write-Error "Specify -ParentPath, -RepoPath, or -RepoPaths"
                return @()
            }
            foreach ($parent in $ParentPath) {
                if (-not (Test-Path $parent)) {
                    Write-Warning "Parent path not found: $parent"
                    continue
                }
                $children = Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue
                foreach ($child in $children) {
                    $gitDir = Join-Path $child.FullName '.git'
                    if (Test-Path $gitDir) {
                        $repos += $child.FullName
                    }
                }
            }
        }
    }

    return $repos
}
#endregion

#region Installation
function Install-HookToRepo {
    param([string]$Repo)

    $repoName = Split-Path $Repo -Leaf
    $hooksDir = Join-Path $Repo '.git' 'hooks'
    $hookDest = Join-Path $hooksDir 'pre-commit'

    # Verify it's a git repo
    if (-not (Test-Path (Join-Path $Repo '.git'))) {
        Write-Warning "[$repoName] Not a git repo, skipping"
        return
    }

    # Create hooks dir if needed
    if (-not (Test-Path $hooksDir)) {
        if ($PSCmdlet.ShouldProcess($hooksDir, "Create hooks directory")) {
            New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
        }
    }

    # Install hook
    $hookExists = Test-Path $hookDest
    if ($hookExists -and -not $Force) {
        Write-Host "  [$repoName] pre-commit hook exists (use -Force to overwrite)" -ForegroundColor Yellow
    } else {
        $action = if ($hookExists) { "Overwrite" } else { "Install" }
        if ($PSCmdlet.ShouldProcess($hookDest, "$action pre-commit hook")) {
            Copy-Item -Path $hookSource -Destination $hookDest -Force
            Write-Host "  [$repoName] pre-commit hook installed" -ForegroundColor Green
        }
    }

    # Add .env to .gitignore if missing
    if (-not $SkipGitignore) {
        $gitignore = Join-Path $Repo '.gitignore'
        $needsEnv = $true

        if (Test-Path $gitignore) {
            $lines = Get-Content $gitignore -ErrorAction SilentlyContinue
            if ($lines | Where-Object { $_.Trim() -eq '.env' }) {
                $needsEnv = $false
            }
        }

        if ($needsEnv) {
            if ($PSCmdlet.ShouldProcess($gitignore, "Add .env to .gitignore")) {
                $entry = "`n# Sensitive environment files`n.env`n.env.local`n.env.*.local`n"
                if (Test-Path $gitignore) {
                    Add-Content -Path $gitignore -Value $entry
                } else {
                    Set-Content -Path $gitignore -Value $entry.TrimStart()
                }
                Write-Host "  [$repoName] Added .env to .gitignore" -ForegroundColor Green
            }
        } else {
            Write-Verbose "  [$repoName] .gitignore already contains .env"
        }
    }
}
#endregion

#region Main
[string[]]$repos = @(Get-TargetRepos)

if ($repos.Count -eq 0) {
    Write-Warning "No repositories found"
    return
}

Write-Host "Installing pre-commit PII hook to $($repos.Count) repo(s)..." -ForegroundColor Cyan
Write-Host "Hook source: $hookSource" -ForegroundColor DarkGray
Write-Host ""

$installed = 0
foreach ($repo in $repos) {
    Install-HookToRepo -Repo $repo
    $installed++
}

Write-Host ""
Write-Host "Done: Processed $installed repo(s)" -ForegroundColor Cyan
#endregion
