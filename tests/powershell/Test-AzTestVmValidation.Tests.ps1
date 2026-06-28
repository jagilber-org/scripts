<#
.SYNOPSIS
    Pester tests for Test-AzTestVmValidation.ps1

.DESCRIPTION
    Validates Test-AzTestVmValidation script including syntax,
    parameter validation, code quality, and security.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\azure\Test-AzTestVmValidation.ps1"
}

Describe "Test-AzTestVmValidation" {
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

        It "Should have a description" {
            $help = Get-Help $scriptPath
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have examples" {
            $help = Get-Help $scriptPath -Full
            $help.Examples | Should -Not -BeNullOrEmpty
        }

        It "Should follow naming conventions" {
            $scriptName = Split-Path $scriptPath -Leaf
            $scriptName | Should -Match '^[A-Z][a-z]+-Az[A-Z][a-zA-Z]+\.ps1$'
        }
    }

    Context "Parameter Validation" {
        It "Should have CmdletBinding attribute" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[CmdletBinding'
        }

        It "Should use approved PowerShell verbs" {
            $scriptName = Split-Path $scriptPath -Leaf
            $verb = $scriptName -replace '-.*', ''
            $approvedVerbs = Get-Verb | Select-Object -ExpandProperty Verb
            $approvedVerbs | Should -Contain $verb
        }

        It "Should require ResourceGroupName as mandatory" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[Parameter\(Mandatory\s*=\s*\$true\)\]'
            $content | Should -Match '\$ResourceGroupName'
        }

        It "Should define PackageName parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$PackageName'
        }

        It "Should define NpmToken as SecureString" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[securestring\]\$NpmToken'
        }

        It "Should define NpmRegistry with ValidateSet" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match "ValidateSet\('github',\s*'npmjs'\)"
        }

        It "Should define VmName parameter for targeting specific VMs" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[string\[\]\]\$VmName'
        }
    }

    Context "Code Quality" {
        It "Should not contain hardcoded credentials" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Not -Match 'password\s*=\s*[''"][^P][^l]'
            $content | Should -Not -Match 'secret\s*=\s*[''"]'
            $content | Should -Not -Match 'ghp_[a-zA-Z0-9]+'
        }

        It "Should use proper error handling" {
            $content = Get-Content $scriptPath -Raw
            ($content -match 'try\s*{' -or $content -match '\$ErrorActionPreference') |
                Should -Be $true
        }

        It "Should verify Azure connection before running" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'Get-AzContext'
        }

        It "Should use Invoke-AzVMRunCommand (not SSH)" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'Invoke-AzVMRunCommand'
            $content | Should -Not -Match 'ssh\s+\w+@'
        }

        It "Should securely handle NpmToken (ZeroFreeBSTR)" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'ZeroFreeBSTR'
        }

        It "Should auto-detect npm scope from package name" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'NpmScope.*PackageName'
        }
    }

    Context "Functionality" {
        It "Should build separate scripts for Linux and Windows" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'build-LinuxScript'
            $content | Should -Match 'build-WindowsScript'
        }

        It "Should parse NODE_VERSION from output" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'NODE_VERSION='
        }

        It "Should parse NPX_RESULT from output" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'NPX_RESULT='
        }

        It "Should output results as structured objects" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[PSCustomObject\]'
            $content | Should -Match 'Format-Table'
        }

        It "Should support saving results to file" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$SaveResults'
            $content | Should -Match '\$ResultsPath'
        }
    }
}
