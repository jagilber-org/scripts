<#
.SYNOPSIS
    Pester tests for GitHub Spec-Kit scaffolding compliance.

.DESCRIPTION
    Validates that all Spec-Kit files exist and are well-formed:
    - constitution.json with required articles
    - .specify/ directory structure
    - .github/copilot-instructions.md
    - sync-constitution.ps1
    - .github/agents/ and .github/prompts/

.NOTES
    Run tests: Invoke-Pester -Path .\tests\powershell\SpecKit.Tests.ps1
#>

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
}

Describe "Spec-Kit Compliance" {

    Context "constitution.json" {
        It "Should exist at repo root" {
            Test-Path (Join-Path $repoRoot 'constitution.json') | Should -Be $true
        }

        It "Should be valid JSON" {
            $path = Join-Path $repoRoot 'constitution.json'
            { Get-Content $path -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should have an articles array" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $constitution.articles | Should -Not -BeNullOrEmpty
            $constitution.articles.Count | Should -BeGreaterOrEqual 1
        }

        It "Should contain quality article" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $ids = $constitution.articles | ForEach-Object { $_.id }
            $ids | Should -Contain 'quality'
        }

        It "Should contain security article" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $ids = $constitution.articles | ForEach-Object { $_.id }
            $ids | Should -Contain 'security'
        }

        It "Should contain architecture article" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $ids = $constitution.articles | ForEach-Object { $_.id }
            $ids | Should -Contain 'architecture'
        }

        It "Should contain governance article" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $ids = $constitution.articles | ForEach-Object { $_.id }
            $ids | Should -Contain 'governance'
        }

        It "Should contain testing article" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            $ids = $constitution.articles | ForEach-Object { $_.id }
            $ids | Should -Contain 'testing'
        }

        It "Each article should have id, title, description, and rules" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            foreach ($article in $constitution.articles) {
                $article.id | Should -Not -BeNullOrEmpty
                $article.title | Should -Not -BeNullOrEmpty
                $article.description | Should -Not -BeNullOrEmpty
                $article.rules | Should -Not -BeNullOrEmpty
                $article.rules.Count | Should -BeGreaterOrEqual 1
            }
        }

        It "Each rule should have id, text, and severity" {
            $path = Join-Path $repoRoot 'constitution.json'
            $constitution = Get-Content $path -Raw | ConvertFrom-Json
            foreach ($article in $constitution.articles) {
                foreach ($rule in $article.rules) {
                    $rule.id | Should -Not -BeNullOrEmpty
                    $rule.text | Should -Not -BeNullOrEmpty
                    $rule.severity | Should -BeIn @('must', 'should', 'may')
                }
            }
        }
    }

    Context ".specify/ directory structure" {
        It "Should have .specify directory" {
            Test-Path (Join-Path $repoRoot '.specify') -PathType Container | Should -Be $true
        }

        It "Should have .specify/memory/constitution.md" {
            Test-Path (Join-Path $repoRoot '.specify\memory\constitution.md') | Should -Be $true
        }

        It "Should have .specify/templates directory" {
            Test-Path (Join-Path $repoRoot '.specify\templates') -PathType Container | Should -Be $true
        }

        It "Should have spec-template.md" {
            Test-Path (Join-Path $repoRoot '.specify\templates\spec-template.md') | Should -Be $true
        }

        It "Should have plan-template.md" {
            Test-Path (Join-Path $repoRoot '.specify\templates\plan-template.md') | Should -Be $true
        }

        It "Should have tasks-template.md" {
            Test-Path (Join-Path $repoRoot '.specify\templates\tasks-template.md') | Should -Be $true
        }

        It "Should have .specify/config/promotion-map.json" {
            Test-Path (Join-Path $repoRoot '.specify\config\promotion-map.json') | Should -Be $true
        }

        It "promotion-map.json should be valid JSON with sources array" {
            $path = Join-Path $repoRoot '.specify\config\promotion-map.json'
            $map = Get-Content $path -Raw | ConvertFrom-Json
            $map.sources | Should -Not -BeNullOrEmpty
            $map.sources.Count | Should -BeGreaterOrEqual 1
        }

        It "Each promotion source should have required fields" {
            $path = Join-Path $repoRoot '.specify\config\promotion-map.json'
            $map = Get-Content $path -Raw | ConvertFrom-Json
            foreach ($source in $map.sources) {
                $source.file | Should -Not -BeNullOrEmpty
                $source.id | Should -Not -BeNullOrEmpty
                $source.title | Should -Not -BeNullOrEmpty
                $source.categories | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context ".github/copilot-instructions.md" {
        It "Should exist" {
            Test-Path (Join-Path $repoRoot '.github\copilot-instructions.md') | Should -Be $true
        }

        It "Should not be empty" {
            $content = Get-Content (Join-Path $repoRoot '.github\copilot-instructions.md') -Raw
            $content.Length | Should -BeGreaterThan 100
        }

        It "Should reference constitution" {
            $content = Get-Content (Join-Path $repoRoot '.github\copilot-instructions.md') -Raw
            $content | Should -Match 'constitution'
        }

        It "Should reference MCP or promote" {
            $content = Get-Content (Join-Path $repoRoot '.github\copilot-instructions.md') -Raw
            $content | Should -Match '(?i)(mcp|promote|promotion)'
        }
    }

    Context "sync-constitution.ps1" {
        It "Should exist at repo root" {
            Test-Path (Join-Path $repoRoot 'sync-constitution.ps1') | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $path = Join-Path $repoRoot 'sync-constitution.ps1'
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $path -Raw), [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It "Should have a -Check parameter" {
            $path = Join-Path $repoRoot 'sync-constitution.ps1'
            $content = Get-Content $path -Raw
            $content | Should -Match '(?i)\-Check'
        }
    }

    Context ".github/agents/" {
        It "Should have agents directory" {
            Test-Path (Join-Path $repoRoot '.github\agents') -PathType Container | Should -Be $true
        }

        It "Should have <Name> agent file" -ForEach @(
            @{ Name = 'constitution' }
            @{ Name = 'specify' }
            @{ Name = 'plan' }
            @{ Name = 'tasks' }
            @{ Name = 'implement' }
        ) {
            Test-Path (Join-Path $repoRoot ".github\agents\$Name.md") | Should -Be $true
        }
    }

    Context ".github/prompts/" {
        It "Should have prompts directory" {
            Test-Path (Join-Path $repoRoot '.github\prompts') -PathType Container | Should -Be $true
        }

        It "Should have <Name> prompt file" -ForEach @(
            @{ Name = 'constitution' }
            @{ Name = 'specify' }
            @{ Name = 'plan' }
            @{ Name = 'tasks' }
            @{ Name = 'implement' }
        ) {
            Test-Path (Join-Path $repoRoot ".github\prompts\$Name.prompt.md") | Should -Be $true
        }
    }
}
