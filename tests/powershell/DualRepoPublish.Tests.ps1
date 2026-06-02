<#
.SYNOPSIS
    Pester tests for dual-repo publishing infrastructure.

.DESCRIPTION
    Validates that dual-repo publishing infrastructure exists and is well-formed:
    - .publish-exclude with required exclusion entries
    - scripts/Publish-ToPublicRepo.ps1 with proper parameters
    - CONTRIBUTING.md with dual-repo model documentation

.NOTES
    Run tests: Invoke-Pester -Path .\tests\powershell\DualRepoPublish.Tests.ps1
#>

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
}

Describe "Dual-Repo Publishing" {

    Context ".publish-exclude" {
        It "Should exist at repo root" {
            Test-Path (Join-Path $repoRoot '.publish-exclude') | Should -Be $true
        }

        It "Should not be empty" {
            $content = Get-Content (Join-Path $repoRoot '.publish-exclude') -Raw
            $content.Trim().Length | Should -BeGreaterThan 0
        }

        It "Should exclude '<Exclusion>'" -ForEach @(
            @{ Exclusion = '.specify/' }
            @{ Exclusion = 'specs/' }
            @{ Exclusion = 'memory/' }
            @{ Exclusion = 'state/' }
            @{ Exclusion = 'logs/' }
            @{ Exclusion = 'test-results/' }
            @{ Exclusion = 'coverage/' }
            @{ Exclusion = '.secrets.baseline' }
        ) {
            $lines = Get-Content (Join-Path $repoRoot '.publish-exclude') |
                Where-Object { $_ -and -not $_.StartsWith('#') } |
                ForEach-Object { $_.Trim() }
            $lines | Should -Contain $Exclusion
        }
    }

    Context "scripts/Publish-ToPublicRepo.ps1" {
        It "Should exist" {
            Test-Path (Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1') | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $path -Raw), [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It "Should have a -Tag parameter" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)\[string\]\s*\$Tag'
        }

        It "Should have a -DryRun switch parameter" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)\[switch\]\s*\$DryRun'
        }

        It "Should have a -Force switch parameter" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)\[switch\]\s*\$Force'
        }

        It "Should reference .publish-exclude" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '\.publish-exclude'
        }

        It "Should verify public remote exists" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)public'
        }

        It "Should check for leaked artifacts" {
            $path = Join-Path $repoRoot 'scripts\Publish-ToPublicRepo.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)(leaked|forbidden|verify)'
        }
    }

    Context "CONTRIBUTING.md" {
        It "Should exist at repo root" {
            Test-Path (Join-Path $repoRoot 'CONTRIBUTING.md') | Should -Be $true
        }

        It "Should mention dual-repo model" {
            $content = Get-Content (Join-Path $repoRoot 'CONTRIBUTING.md') -Raw
            $content | Should -Match '(?i)dual.?repo'
        }

        It "Should mention jagilber-org/scripts as public mirror" {
            $content = Get-Content (Join-Path $repoRoot 'CONTRIBUTING.md') -Raw
            $content | Should -Match 'jagilber-org/scripts'
        }

        It "Should mention Publish-ToPublicRepo" {
            $content = Get-Content (Join-Path $repoRoot 'CONTRIBUTING.md') -Raw
            $content | Should -Match 'Publish-ToPublicRepo'
        }
    }
}
