<#
.SYNOPSIS
    Install pre-commit hook for preventing sensitive data commits

.DESCRIPTION
    This script installs a pre-commit hook that prevents:
    - .env files from being committed
    - .env variable values from appearing in staged files
    - Common credential patterns (with warnings)
    
    The hook includes both PowerShell and shell implementations for 
    cross-platform support.

.PARAMETER SourceRepository
    Path to repository containing the reference pre-commit hook implementation.
    Defaults to current repository.

.PARAMETER TargetRepository
    Path to repository where the pre-commit hook should be installed.
    Defaults to current repository.

.PARAMETER Force
    Overwrite existing pre-commit hook if present.

.PARAMETER IncludeTests
    Also copy the test-pre-commit-hook.ps1 test suite.

.PARAMETER IncludeDocs
    Also copy the PRE-COMMIT-HOOK.md documentation.

.EXAMPLE
    .\setup-pre-commit-hook.ps1
    Install hook in current repository

.EXAMPLE
    .\setup-pre-commit-hook.ps1 -TargetRepository "C:\repos\myproject" -IncludeTests -IncludeDocs
    Install hook, tests, and docs to another repository

.EXAMPLE
    .\setup-pre-commit-hook.ps1 -Force
    Reinstall hook, overwriting existing hook

.NOTES
    Author: Repository Security Team
    Version: 1.0
    Date: 2025-10-22
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$SourceRepository = $PSScriptRoot,
    
    [Parameter()]
    [string]$TargetRepository = $PSScriptRoot,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$IncludeTests,
    
    [Parameter()]
    [switch]$IncludeDocs
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    
    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    
    $prefix = switch ($Type) {
        'Success' { '✓' }
        'Warning' { '⚠' }
        'Error' { '✗' }
        'Info' { '→' }
        default { ' ' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

# Verify we're in a git repository
$targetGitDir = Join-Path $TargetRepository '.git'
if (-not (Test-Path $targetGitDir)) {
    Write-Status "Target is not a git repository: $TargetRepository" -Type Error
    exit 1
}

Write-Status "Installing pre-commit hook to: $TargetRepository" -Type Info
Write-Host ""

# Define source and target paths
$sourceHooksDir = Join-Path $SourceRepository '.git\hooks'
$targetHooksDir = Join-Path $TargetRepository '.git\hooks'

$files = @{
    Hook = @{
        Source = Join-Path $sourceHooksDir 'pre-commit'
        Target = Join-Path $targetHooksDir 'pre-commit'
        Required = $true
    }
    PowerShellHook = @{
        Source = Join-Path $sourceHooksDir 'pre-commit.ps1'
        Target = Join-Path $targetHooksDir 'pre-commit.ps1'
        Required = $true
    }
    TestSuite = @{
        Source = Join-Path $SourceRepository 'test-pre-commit-hook.ps1'
        Target = Join-Path $TargetRepository 'test-pre-commit-hook.ps1'
        Required = $false
        IncludeFlag = $IncludeTests
    }
    Documentation = @{
        Source = Join-Path $SourceRepository '.github\PRE-COMMIT-HOOK.md'
        Target = Join-Path $TargetRepository '.github\PRE-COMMIT-HOOK.md'
        Required = $false
        IncludeFlag = $IncludeDocs
    }
}

# Verify source files exist
$missingFiles = @()
foreach ($fileInfo in $files.Values | Where-Object { $_.Required -or $_.IncludeFlag }) {
    if (-not (Test-Path $fileInfo.Source)) {
        $missingFiles += $fileInfo.Source
    }
}

if ($missingFiles) {
    Write-Status "Missing source files:" -Type Error
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Install files
$installedCount = 0
$skippedCount = 0

foreach ($name in $files.Keys) {
    $fileInfo = $files[$name]
    
    # Skip optional files if not requested
    if (-not $fileInfo.Required -and -not $fileInfo.IncludeFlag) {
        continue
    }
    
    $targetDir = Split-Path $fileInfo.Target -Parent
    
    # Create target directory if needed
    if (-not (Test-Path $targetDir)) {
        if ($PSCmdlet.ShouldProcess($targetDir, "Create directory")) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Write-Status "Created directory: $targetDir" -Type Info
        }
    }
    
    # Check if target exists
    if ((Test-Path $fileInfo.Target) -and -not $Force) {
        Write-Status "Skipped $name (already exists, use -Force to overwrite)" -Type Warning
        $skippedCount++
        continue
    }
    
    # Copy file
    if ($PSCmdlet.ShouldProcess($fileInfo.Target, "Copy $name")) {
        Copy-Item -Path $fileInfo.Source -Destination $fileInfo.Target -Force
        Write-Status "Installed $name" -Type Success
        $installedCount++
        
        # Show file info
        $fileItem = Get-Item $fileInfo.Target
        Write-Host "  Size: $($fileItem.Length) bytes" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Status "Installation Summary:" -Type Info
Write-Host "  Installed: $installedCount files" -ForegroundColor Green
if ($skippedCount -gt 0) {
    Write-Host "  Skipped:   $skippedCount files (use -Force to overwrite)" -ForegroundColor Yellow
}

# Verify .gitignore includes .env
Write-Host ""
Write-Status "Checking .gitignore configuration..." -Type Info

$gitignorePath = Join-Path $TargetRepository '.gitignore'
if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    
    if ($gitignoreContent -match '\.env') {
        Write-Status ".gitignore includes .env patterns" -Type Success
    } else {
        Write-Status ".gitignore missing .env patterns" -Type Warning
        Write-Host "  Add the following to .gitignore:" -ForegroundColor Yellow
        Write-Host "    .env" -ForegroundColor White
        Write-Host "    .env.local" -ForegroundColor White
        Write-Host "    !.env.example" -ForegroundColor White
    }
} else {
    Write-Status "No .gitignore found - create one with .env patterns" -Type Warning
}

# Check for .env.example
$envExamplePath = Join-Path $TargetRepository '.env.example'
if (Test-Path $envExamplePath) {
    Write-Status ".env.example found" -Type Success
} else {
    Write-Status "Consider creating .env.example with placeholder values" -Type Warning
}

# Test the hook if in target repository
if ($TargetRepository -eq $PSScriptRoot -or (Resolve-Path $TargetRepository) -eq (Resolve-Path $PSScriptRoot)) {
    Write-Host ""
    Write-Status "Testing the installed hook..." -Type Info
    
    try {
        $testResult = & (Join-Path $targetHooksDir 'pre-commit.ps1') -ErrorAction Stop
        Write-Status "Hook test passed" -Type Success
    } catch {
        Write-Status "Hook test had warnings (may be normal)" -Type Warning
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Status "Installation complete!" -Type Success
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review the hook configuration in .git/hooks/" -ForegroundColor White
if ($IncludeTests) {
    Write-Host "  2. Run tests: .\test-pre-commit-hook.ps1" -ForegroundColor White
}
if ($IncludeDocs) {
    Write-Host "  3. Review documentation: .github\PRE-COMMIT-HOOK.md" -ForegroundColor White
}
Write-Host "  4. Ensure .gitignore includes .env patterns" -ForegroundColor White
Write-Host "  5. Create .env.example with placeholder values" -ForegroundColor White
Write-Host ""
Write-Host "The hook will run automatically on every commit." -ForegroundColor Gray
Write-Host "To bypass (use carefully): git commit --no-verify" -ForegroundColor Gray
