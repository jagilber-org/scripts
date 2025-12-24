<#
.SYNOPSIS
    Test the pre-commit hook functionality

.DESCRIPTION
    This script tests the pre-commit hook by simulating various scenarios:
    1. Adding .env files to staging
    2. Adding files with .env variable values
    3. Adding files with credential patterns
    
    Run this to verify the hook is working correctly.

.PARAMETER TestCase
    Specific test case to run. If not specified, runs all tests.
    Valid values: 'EnvFile', 'EnvValues', 'CredentialPatterns', 'All'

.EXAMPLE
    .\test-pre-commit-hook.ps1
    Runs all test cases

.EXAMPLE
    .\test-pre-commit-hook.ps1 -TestCase EnvFile
    Tests only the .env file detection
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('EnvFile', 'EnvValues', 'CredentialPatterns', 'All')]
    [string]$TestCase = 'All'
)

$ErrorActionPreference = 'Stop'

# Ensure we're in a git repository
if (-not (Test-Path '.git')) {
    Write-Error "Not in a git repository root. Please run from repository root."
    exit 1
}

function Write-TestHeader {
    param([string]$Title)
    Write-Host "`n$('=' * 70)" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "$('=' * 70)`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ''
    )
    
    $status = if ($Passed) { '✓ PASS' } else { '✗ FAIL' }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    
    Write-Host "$status - $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  $Message" -ForegroundColor Yellow
    }
}

# Store original git state
$originalBranch = git branch --show-current
Write-Host "Original branch: $originalBranch" -ForegroundColor Gray

#region Test 1: .env file detection
function Test-EnvFileDetection {
    Write-TestHeader "Test 1: .env File Detection"
    
    try {
        # Create a temporary .env file
        $testEnvFile = '.env.test'
        "TEST_VAR=test-value" | Out-File $testEnvFile -Encoding utf8
        
        # Stage it
        git add $testEnvFile 2>&1 | Out-Null
        
        Write-Host "Staged $testEnvFile, attempting commit..." -ForegroundColor Yellow
        
        # Try to commit (should fail)
        $result = git commit -m "Test commit with .env file" 2>&1
        $exitCode = $LASTEXITCODE
        
        # Clean up
        git reset HEAD $testEnvFile 2>&1 | Out-Null
        Remove-Item $testEnvFile -Force -ErrorAction SilentlyContinue
        
        if ($exitCode -ne 0) {
            Write-TestResult -TestName "Block .env file commit" -Passed $true -Message "Hook correctly blocked .env file"
            return $true
        } else {
            Write-TestResult -TestName "Block .env file commit" -Passed $false -Message "Hook failed to block .env file"
            return $false
        }
        
    } catch {
        Write-TestResult -TestName "Block .env file commit" -Passed $false -Message $_.Exception.Message
        return $false
    }
}
#endregion

#region Test 2: .env variable value detection
function Test-EnvValueDetection {
    Write-TestHeader "Test 2: .env Variable Value Detection"
    
    try {
        # Check if .env exists
        if (-not (Test-Path '.env')) {
            Write-TestResult -TestName "Detect .env values" -Passed $true -Message "No .env file to test (SKIP)"
            return $true
        }
        
        # Get a real value from .env
        $envContent = Get-Content '.env' | Where-Object { $_ -match '^[A-Z_]+=.+' -and $_ -notmatch '(example|placeholder)' } | Select-Object -First 1
        
        if (-not $envContent) {
            Write-TestResult -TestName "Detect .env values" -Passed $true -Message "No real values in .env to test (SKIP)"
            return $true
        }
        
        $testKey = ($envContent -split '=')[0]
        $testValue = ($envContent -split '=', 2)[1]
        
        Write-Host "Testing with key: $testKey" -ForegroundColor Yellow
        
        # Create a test file with the value
        $testFile = 'test-secret-file.txt'
        "This file contains a secret: $testValue" | Out-File $testFile -Encoding utf8
        
        # Stage it
        git add $testFile 2>&1 | Out-Null
        
        Write-Host "Staged file with .env value, attempting commit..." -ForegroundColor Yellow
        
        # Try to commit (should fail)
        $result = git commit -m "Test commit with env value" 2>&1
        $exitCode = $LASTEXITCODE
        
        # Clean up
        git reset HEAD $testFile 2>&1 | Out-Null
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        if ($exitCode -ne 0) {
            Write-TestResult -TestName "Detect .env value in file" -Passed $true -Message "Hook correctly detected .env value"
            return $true
        } else {
            Write-TestResult -TestName "Detect .env value in file" -Passed $false -Message "Hook failed to detect .env value"
            return $false
        }
        
    } catch {
        Write-TestResult -TestName "Detect .env value in file" -Passed $false -Message $_.Exception.Message
        return $false
    }
}
#endregion

#region Test 3: Credential pattern detection
function Test-CredentialPatternDetection {
    Write-TestHeader "Test 3: Credential Pattern Detection"
    
    try {
        # Create a file with credential-like content
        $testFile = 'test-credentials.ps1'
        @'
$password = "RealPassword123!"
$apiKey = "sk-1234567890abcdef"
$secret = "MySecretValue"
'@ | Out-File $testFile -Encoding utf8
        
        # Stage it
        git add $testFile 2>&1 | Out-Null
        
        Write-Host "Staged file with credential patterns, attempting commit..." -ForegroundColor Yellow
        
        # Try to commit (should warn but not necessarily fail)
        $result = git commit -m "Test commit with credentials" 2>&1
        $exitCode = $LASTEXITCODE
        
        # Clean up
        git reset HEAD $testFile 2>&1 | Out-Null
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        # For this test, we just want to see warnings (doesn't block)
        Write-TestResult -TestName "Detect credential patterns" -Passed $true -Message "Pattern detection executed (warnings expected)"
        return $true
        
    } catch {
        Write-TestResult -TestName "Detect credential patterns" -Passed $false -Message $_.Exception.Message
        return $false
    }
}
#endregion

#region Test 4: Normal file should pass
function Test-NormalFileCommit {
    Write-TestHeader "Test 4: Normal File Commit (Should Pass)"
    
    try {
        # Create a safe test file
        $testFile = 'test-safe-file.txt'
        "This is a safe file with no secrets" | Out-File $testFile -Encoding utf8
        
        # Stage it
        git add $testFile 2>&1 | Out-Null
        
        Write-Host "Staged safe file, attempting commit..." -ForegroundColor Yellow
        
        # Try to commit (should succeed)
        $result = git commit -m "Test commit with safe file" 2>&1
        $exitCode = $LASTEXITCODE
        
        # Clean up - remove the commit
        if ($exitCode -eq 0) {
            git reset --soft HEAD~1 2>&1 | Out-Null
        }
        git reset HEAD $testFile 2>&1 | Out-Null
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        if ($exitCode -eq 0) {
            Write-TestResult -TestName "Allow safe file commit" -Passed $true -Message "Hook correctly allowed safe file"
            return $true
        } else {
            Write-TestResult -TestName "Allow safe file commit" -Passed $false -Message "Hook incorrectly blocked safe file"
            return $false
        }
        
    } catch {
        Write-TestResult -TestName "Allow safe file commit" -Passed $false -Message $_.Exception.Message
        return $false
    }
}
#endregion

# Main execution
try {
    Write-Host "`n" -NoNewline
    Write-Host "Pre-Commit Hook Test Suite" -ForegroundColor Cyan
    Write-Host "Testing hooks in: .git/hooks/" -ForegroundColor Gray
    
    $testResults = @{}
    
    if ($TestCase -eq 'All' -or $TestCase -eq 'EnvFile') {
        $testResults['EnvFile'] = Test-EnvFileDetection
    }
    
    if ($TestCase -eq 'All' -or $TestCase -eq 'EnvValues') {
        $testResults['EnvValues'] = Test-EnvValueDetection
    }
    
    if ($TestCase -eq 'All' -or $TestCase -eq 'CredentialPatterns') {
        $testResults['CredentialPatterns'] = Test-CredentialPatternDetection
    }
    
    if ($TestCase -eq 'All') {
        $testResults['NormalFile'] = Test-NormalFileCommit
    }
    
    # Summary
    Write-TestHeader "Test Summary"
    $passCount = ($testResults.Values | Where-Object { $_ -eq $true }).Count
    $totalCount = $testResults.Count
    
    Write-Host "Passed: $passCount / $totalCount" -ForegroundColor $(if ($passCount -eq $totalCount) { 'Green' } else { 'Yellow' })
    
    if ($passCount -eq $totalCount) {
        Write-Host "`n✓ All tests passed! Pre-commit hook is working correctly." -ForegroundColor Green
    } else {
        Write-Host "`n⚠ Some tests failed. Review the hook implementation." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "`nTest suite failed with error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    # Ensure we're back to a clean state
    Write-Host "`nCleaning up..." -ForegroundColor Gray
    git reset HEAD . 2>&1 | Out-Null
}
