<#
.SYNOPSIS
    Pester tests for Invoke-KustoQuery.ps1

.DESCRIPTION
    Validates Kusto query script functionality.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\data-collection\Invoke-KustoQuery.ps1"
}

Describe "Invoke-KustoQuery" {
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

        It "Should have synopsis and description" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should use approved verb 'Invoke'" {
            $scriptName = Split-Path $scriptPath -Leaf
            $scriptName | Should -Match '^Invoke-'
        }
    }

    Context "Code Quality" {
        It "Should not contain connection strings" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Not -Match 'Data Source=.*Password='
            $content | Should -Not -Match 'AccountKey\s*=\s*[''"][^''"]{20,}'
        }

        It "Should have parameter validation" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[Parameter\('
        }

        It "Should handle errors appropriately" {
            $content = Get-Content $scriptPath -Raw
            ($content -match 'try\s*{' -or $content -match 'catch\s*{') | 
                Should -Be $true
        }
    }

    Context "Documentation" {
        It "Should have example usage" {
            $help = Get-Help $scriptPath
            $help.Examples | Should -Not -BeNullOrEmpty
        }
    }
}
