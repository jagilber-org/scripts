<#
.SYNOPSIS
    Runs all Pester tests for the scripts repository.

.DESCRIPTION
    Executes all PowerShell script tests and generates a summary report.
    Supports code coverage analysis and CI/CD integration.

.PARAMETER Path
    Path to test files. Defaults to tests/powershell directory.

.PARAMETER CodeCoverage
    Enable code coverage analysis.

.PARAMETER Tag
    Run only tests with specific tags (e.g., 'Unit', 'Integration').

.PARAMETER OutputFormat
    Output format for results: NUnitXml, JUnitXml, or Console (default).

.EXAMPLE
    .\Run-Tests.ps1
    Runs all tests with console output.

.EXAMPLE
    .\Run-Tests.ps1 -CodeCoverage
    Runs all tests with code coverage report.

.EXAMPLE
    .\Run-Tests.ps1 -Tag 'Unit'
    Runs only unit tests.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path $PSScriptRoot "tests\powershell"),

    [Parameter()]
    [switch]$CodeCoverage,

    [Parameter()]
    [string[]]$Tag,

    [Parameter()]
    [ValidateSet('Console', 'NUnitXml', 'JUnitXml')]
    [string]$OutputFormat = 'Console'
)

$ErrorActionPreference = 'Stop'

# Verify Pester is installed
Write-Host "`nChecking Pester installation..." -ForegroundColor Cyan
try {
    $pesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    
    if (-not $pesterModule) {
        Write-Host "Pester not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
        Import-Module Pester -Force
    }
    elseif ($pesterModule.Version -lt [version]"5.0.0") {
        Write-Host "Pester $($pesterModule.Version) found. Updating to v5+..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser -AllowClobber
        Import-Module Pester -Force
    }
    else {
        Write-Host "Pester $($pesterModule.Version) is installed" -ForegroundColor Green
        Import-Module Pester -Force
    }
}
catch {
    Write-Error "Failed to setup Pester: $_"
    exit 1
}

# Configure Pester
Write-Host "`nConfiguring Pester..." -ForegroundColor Cyan
$config = New-PesterConfiguration

# Set test path
$config.Run.Path = $Path
$config.Run.PassThru = $true

# Set output
$config.Output.Verbosity = 'Detailed'

# Configure tags
if ($Tag) {
    $config.Filter.Tag = $Tag
    Write-Host "Running tests with tags: $($Tag -join ', ')" -ForegroundColor Cyan
}

# Configure code coverage
if ($CodeCoverage) {
    Write-Host "Code coverage enabled" -ForegroundColor Cyan
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path $PSScriptRoot "powershell\**\*.ps1"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot "coverage.xml"
}

# Configure output format
if ($OutputFormat -ne 'Console') {
    $outputPath = Join-Path $PSScriptRoot "test-results.$($OutputFormat.ToLower())"
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = $OutputFormat
    $config.TestResult.OutputPath = $outputPath
    Write-Host "Test results will be written to: $outputPath" -ForegroundColor Cyan
}

# Run tests
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "RUNNING TESTS" -ForegroundColor Cyan
Write-Host ("=" * 80) + "`n" -ForegroundColor Cyan

$result = Invoke-Pester -Configuration $config

# Display summary
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

$totalTests = $result.TotalCount
$passedTests = $result.PassedCount
$failedTests = $result.FailedCount
$skippedTests = $result.SkippedCount
$duration = $result.Duration.TotalSeconds

Write-Host "Total:   $totalTests tests" -ForegroundColor White
Write-Host "Passed:  $passedTests tests" -ForegroundColor Green
if ($failedTests -gt 0) {
    Write-Host "Failed:  $failedTests tests" -ForegroundColor Red
}
else {
    Write-Host "Failed:  $failedTests tests" -ForegroundColor Green
}
if ($skippedTests -gt 0) {
    Write-Host "Skipped: $skippedTests tests" -ForegroundColor Yellow
}
Write-Host "Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor White

# Code coverage summary
if ($CodeCoverage -and $result.CodeCoverage) {
    $coverage = $result.CodeCoverage
    $coveragePercent = [math]::Round(($coverage.CoveredPercent), 2)
    
    Write-Host "`nCode Coverage:" -ForegroundColor Cyan
    Write-Host "  Covered: $coveragePercent%" -ForegroundColor $(if ($coveragePercent -ge 70) { 'Green' } else { 'Yellow' })
    Write-Host "  Commands Analyzed: $($coverage.NumberOfCommandsAnalyzed)" -ForegroundColor White
    Write-Host "  Commands Executed: $($coverage.NumberOfCommandsExecuted)" -ForegroundColor White
    Write-Host "  Coverage report: coverage.xml" -ForegroundColor White
}

Write-Host ("=" * 80) + "`n" -ForegroundColor Cyan

# Exit with appropriate code
if ($failedTests -gt 0) {
    Write-Host "TESTS FAILED" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
