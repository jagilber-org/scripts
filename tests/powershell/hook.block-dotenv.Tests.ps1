<#
.SYNOPSIS
    Pester tests for hooks/block-dotenv.ps1
.NOTES
    Requires: Pester 5.x+
#>

BeforeAll {
    $script:hookPath = Join-Path $PSScriptRoot '..\..\hooks\block-dotenv.ps1'

    function Invoke-BlockDotenv {
        param([string[]]$Files)
        $output = pwsh -NoProfile -NonInteractive -File $script:hookPath @Files 2>&1
        [PSCustomObject]@{
            Output   = $output -join "`n"
            ExitCode = $LASTEXITCODE
        }
    }
}

Describe 'Script Validation' {
    It 'Should exist at hooks/block-dotenv.ps1' {
        Test-Path $script:hookPath | Should -Be $true
    }

    It 'Should have no parse errors' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'block-dotenv behaviour' {
    BeforeAll {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-block-dotenv-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Blocked files' {
        It 'Should block a bare .env file' {
            $f = Join-Path $script:tmpDir '.env'
            'SECRET=abc' | Set-Content $f
            $result = Invoke-BlockDotenv -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'ERROR'
        }

        It 'Should block .env.production' {
            $f = Join-Path $script:tmpDir '.env.production'
            'SECRET=abc' | Set-Content $f
            $result = Invoke-BlockDotenv -Files $f
            $result.ExitCode | Should -Be 1
        }

        It 'Should block .env.local' {
            $f = Join-Path $script:tmpDir '.env.local'
            'SECRET=abc' | Set-Content $f
            $result = Invoke-BlockDotenv -Files $f
            $result.ExitCode | Should -Be 1
        }

        It 'Should block when mixed with a safe file' {
            $safe = Join-Path $script:tmpDir 'README.md'
            $env  = Join-Path $script:tmpDir '.env'
            'safe' | Set-Content $safe
            'SECRET=abc' | Set-Content $env
            $result = Invoke-BlockDotenv -Files $safe, $env
            $result.ExitCode | Should -Be 1
        }
    }

    Context 'Allowed files' {
        It 'Should allow .env.example' {
            $f = Join-Path $script:tmpDir '.env.example'
            'AZURE_SUBSCRIPTION_ID=' | Set-Content $f
            $result = Invoke-BlockDotenv -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should allow a regular .ps1 file' {
            $f = Join-Path $script:tmpDir 'script.ps1'
            'Write-Host hello' | Set-Content $f
            $result = Invoke-BlockDotenv -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should allow when no files are passed' {
            $result = Invoke-BlockDotenv -Files @()
            $result.ExitCode | Should -Be 0
        }
    }
}
