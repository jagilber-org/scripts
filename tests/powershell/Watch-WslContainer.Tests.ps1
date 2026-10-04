<#
.SYNOPSIS
    Pester tests for Watch-WslContainer.ps1.

.DESCRIPTION
    Validates script existence, syntax, and comment-based help for the WSL
    container live dashboard.
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot "..\..\powershell\wslc\Watch-WslContainer.ps1"
}

Describe "Watch-WslContainer" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $script:scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script:scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have a synopsis" {
            (Get-Help $script:scriptPath).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            (Get-Help $script:scriptPath).Description | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter Validation" {
        It "Should expose refresh, iteration, and view parameters" {
            $params = (Get-Command $script:scriptPath).Parameters.Keys
            $params | Should -Contain 'RefreshIntervalSeconds'
            $params | Should -Contain 'MaxIterations'
            $params | Should -Contain 'ShowStopped'
            $params | Should -Contain 'HideImages'
            $params | Should -Contain 'ImageDetails'
            $params | Should -Contain 'NoHyperlink'
            $params | Should -Contain 'WslcPath'
        }

        It "Should constrain RefreshIntervalSeconds to a valid range" {
            $attr = (Get-Command $script:scriptPath).Parameters['RefreshIntervalSeconds'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $attr.MinRange | Should -Be 1
            $attr.MaxRange | Should -Be 3600
        }
    }
}
