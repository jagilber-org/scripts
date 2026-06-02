<#
.SYNOPSIS
    Pester tests for Import-CentralEnv.ps1.

.DESCRIPTION
    Tests for the Import-CentralEnv script that loads central environment
    variables from C:\github\.env into the current session.

.NOTES
    Run tests: Invoke-Pester -Path .\tests\powershell\Import-CentralEnv.Tests.ps1
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Script not found: $scriptPath"
    }
}

Describe "Import-CentralEnv" {
    Context "Script Validation" {
        It "Should exist" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            Test-Path $scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have a synopsis" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $help = Get-Help $scriptPath
            $help.Description | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter Validation" {
        It "Should have Path parameter" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $params = (Get-Command $scriptPath).Parameters
            $params.Keys | Should -Contain 'Path'
        }

        It "Should have Force parameter" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $params = (Get-Command $scriptPath).Parameters
            $params.Keys | Should -Contain 'Force'
        }

        It "Should have Quiet parameter" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\automation\Import-CentralEnv.ps1"
            $params = (Get-Command $scriptPath).Parameters
            $params.Keys | Should -Contain 'Quiet'
        }
    }

    Context "Functionality Tests" {
        BeforeAll {
            $testEnvFile = Join-Path $TestDrive 'test.env'
        }

        It "Should warn when .env file does not exist" {
            $missingPath = Join-Path $TestDrive 'missing.env'
            $result = & $scriptPath -Path $missingPath 3>&1
            $result | Should -BeLike '*not found*'
        }

        It "Should load variables from a valid .env file" {
            $uniqueKey = "PESTER_TEST_IMPORT_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Set-Content -Path $testEnvFile -Value "$uniqueKey=hello_world"
            try {
                & $scriptPath -Path $testEnvFile -Quiet
                [System.Environment]::GetEnvironmentVariable($uniqueKey, 'Process') | Should -Be 'hello_world'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
            }
        }

        It "Should skip comments and blank lines" {
            $uniqueKey = "PESTER_TEST_SKIP_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Set-Content -Path $testEnvFile -Value @"
# This is a comment
$uniqueKey=valid_value

"@
            try {
                & $scriptPath -Path $testEnvFile -Quiet
                [System.Environment]::GetEnvironmentVariable($uniqueKey, 'Process') | Should -Be 'valid_value'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
            }
        }

        It "Should not override existing variables without -Force" {
            $uniqueKey = "PESTER_TEST_NOFORCE_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            [System.Environment]::SetEnvironmentVariable($uniqueKey, 'original', 'Process')
            Set-Content -Path $testEnvFile -Value "$uniqueKey=override_attempt"
            try {
                & $scriptPath -Path $testEnvFile -Quiet
                [System.Environment]::GetEnvironmentVariable($uniqueKey, 'Process') | Should -Be 'original'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
            }
        }

        It "Should override existing variables with -Force" {
            $uniqueKey = "PESTER_TEST_FORCE_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            [System.Environment]::SetEnvironmentVariable($uniqueKey, 'original', 'Process')
            Set-Content -Path $testEnvFile -Value "$uniqueKey=forced_value"
            try {
                & $scriptPath -Path $testEnvFile -Force -Quiet
                [System.Environment]::GetEnvironmentVariable($uniqueKey, 'Process') | Should -Be 'forced_value'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
            }
        }

        It "Should strip surrounding quotes from values" {
            $uniqueKey = "PESTER_TEST_QUOTES_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Set-Content -Path $testEnvFile -Value "$uniqueKey=`"quoted_value`""
            try {
                & $scriptPath -Path $testEnvFile -Quiet
                [System.Environment]::GetEnvironmentVariable($uniqueKey, 'Process') | Should -Be 'quoted_value'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
            }
        }
    }
}
