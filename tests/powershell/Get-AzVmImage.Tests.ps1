<#
.SYNOPSIS
    Pester tests for Get-AzVmImage.ps1

.DESCRIPTION
    Validates Get-AzVmImage script functionality including syntax,
    parameter validation, and basic operation.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\azure\Get-AzVmImage.ps1"
}

Describe "Get-AzVmImage" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have help documentation" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should follow naming conventions" {
            $scriptName = Split-Path $scriptPath -Leaf
            $scriptName | Should -Match '^[A-Z][a-z]+-Az[A-Z][a-zA-Z]+\.ps1$'
        }
    }

    Context "Parameter Validation" {
        It "Should have CmdletBinding attribute" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]'
        }

        It "Should use approved PowerShell verbs" {
            $scriptName = Split-Path $scriptPath -Leaf
            $verb = $scriptName -replace '-.*', ''
            $approvedVerbs = Get-Verb | Select-Object -ExpandProperty Verb
            $approvedVerbs | Should -Contain $verb
        }
    }

    Context "Code Quality" {
        It "Should not contain hardcoded credentials" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Not -Match 'password\s*=\s*[''"]'
            $content | Should -Not -Match 'secret\s*=\s*[''"]'
        }

        It "Should use proper error handling" {
            $content = Get-Content $scriptPath -Raw
            # Check for try/catch or ErrorActionPreference
            ($content -match 'try\s*{' -or $content -match '\$ErrorActionPreference') | 
                Should -Be $true
        }
    }
}
