<#
.SYNOPSIS
    Pester tests for constitution sync functionality.

.DESCRIPTION
    Validates that sync-constitution.ps1 correctly generates constitution.md
    from constitution.json and supports -Check mode for drift detection.

.NOTES
    Run tests: Invoke-Pester -Path .\tests\powershell\ConstitutionSync.Tests.ps1
#>

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $syncScript = Join-Path $repoRoot 'sync-constitution.ps1'
    $constitutionJson = Join-Path $repoRoot 'constitution.json'
    $constitutionMd = Join-Path $repoRoot '.specify\memory\constitution.md'
}

Describe "Constitution Sync" {

    Context "Generation" {
        It "sync-constitution.ps1 should exist" {
            Test-Path $syncScript | Should -Be $true
        }

        It "constitution.json should exist" {
            Test-Path $constitutionJson | Should -Be $true
        }

        It "Should generate constitution.md without error" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            { & $syncScript } | Should -Not -Throw
        }

        It "Generated constitution.md should exist" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            & $syncScript
            Test-Path $constitutionMd | Should -Be $true
        }

        It "Generated markdown should contain article titles from JSON" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            & $syncScript
            $json = Get-Content $constitutionJson -Raw | ConvertFrom-Json
            $md = Get-Content $constitutionMd -Raw

            foreach ($article in $json.articles) {
                $md | Should -Match ([regex]::Escape($article.title))
            }
        }

        It "Generated markdown should contain rule text from JSON" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            & $syncScript
            $json = Get-Content $constitutionJson -Raw | ConvertFrom-Json
            $md = Get-Content $constitutionMd -Raw

            # Check at least the first rule of each article appears
            foreach ($article in $json.articles) {
                if ($article.rules.Count -gt 0) {
                    $firstRuleText = $article.rules[0].text
                    $md | Should -Match ([regex]::Escape($firstRuleText))
                }
            }
        }
    }

    Context "Check Mode" {
        It "Should exit 0 when constitution.md is in sync" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            # First generate to ensure in sync
            & $syncScript
            $result = & $syncScript -Check
            $LASTEXITCODE | Should -Be 0
        }

        It "Should exit 1 when constitution.md is drifted" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            # Generate first
            & $syncScript

            # Corrupt the generated file
            $originalContent = Get-Content $constitutionMd -Raw
            try {
                Set-Content $constitutionMd -Value "DRIFTED CONTENT"
                & $syncScript -Check
                $LASTEXITCODE | Should -Be 1
            }
            finally {
                # Restore original
                Set-Content $constitutionMd -Value $originalContent -NoNewline
            }
        }

        It "Should exit 1 when constitution.md is missing" {
            if (-not (Test-Path $syncScript) -or -not (Test-Path $constitutionJson)) {
                Set-ItResult -Skipped -Because 'prerequisites missing'
                return
            }
            # Generate first, then remove
            & $syncScript
            $originalContent = Get-Content $constitutionMd -Raw
            try {
                Remove-Item $constitutionMd -Force
                & $syncScript -Check
                $LASTEXITCODE | Should -Be 1
            }
            finally {
                # Restore
                $dir = Split-Path $constitutionMd -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Set-Content $constitutionMd -Value $originalContent -NoNewline
            }
        }
    }
}
