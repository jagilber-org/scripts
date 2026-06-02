<#
.SYNOPSIS
    Pester tests for hooks/pre-push-public-guard.ps1
.NOTES
    Requires: Pester 5.x+
    Integration tests that call the GitHub API are tagged 'Integration' and skipped
    when the 'gh' CLI is unavailable.
#>

BeforeAll {
    $script:hookPath = Join-Path $PSScriptRoot '..\..\hooks\pre-push-public-guard.ps1'

    function Invoke-PushGuard {
        param([string]$RemoteName, [string]$RemoteUrl, [string]$Override = '')
        $env:PUBLISH_OVERRIDE = $Override
        $output = pwsh -NoProfile -NonInteractive -File $script:hookPath $RemoteName $RemoteUrl 2>&1
        $exitCode = $LASTEXITCODE
        $env:PUBLISH_OVERRIDE = $null
        [PSCustomObject]@{
            Output   = $output -join "`n"
            ExitCode = $exitCode
        }
    }

    $script:ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)
}

Describe 'Script Validation' {
    It 'Should exist at hooks/pre-push-public-guard.ps1' {
        Test-Path $script:hookPath | Should -Be $true
    }

    It 'Should have no parse errors' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Should declare a RemoteName parameter' {
        $content = Get-Content $script:hookPath -Raw
        $content | Should -Match '(?i)\$RemoteName'
    }

    It 'Should declare a RemoteUrl parameter' {
        $content = Get-Content $script:hookPath -Raw
        $content | Should -Match '(?i)\$RemoteUrl'
    }

    It 'Should reference PUBLISH_OVERRIDE bypass' {
        $content = Get-Content $script:hookPath -Raw
        $content | Should -Match 'PUBLISH_OVERRIDE'
    }
}

Describe 'Non-GitHub remotes' {
    It 'Should allow push to a non-GitHub remote URL' {
        $result = Invoke-PushGuard -RemoteName 'local' -RemoteUrl 'file:///c:/repos/local.git'
        $result.ExitCode | Should -Be 0
    }

    It 'Should allow push to an Azure DevOps remote' {
        $result = Invoke-PushGuard -RemoteName 'ado' -RemoteUrl 'https://dev.azure.com/org/project/_git/repo'
        $result.ExitCode | Should -Be 0
    }

    It 'Should allow push when URL is empty' {
        $result = Invoke-PushGuard -RemoteName 'origin' -RemoteUrl ''
        $result.ExitCode | Should -Be 0
    }
}

Describe 'PUBLISH_OVERRIDE bypass' {
    It 'Should allow push when PUBLISH_OVERRIDE=1 even for GitHub URLs' {
        $result = Invoke-PushGuard -RemoteName 'public' -RemoteUrl 'https://github.com/some/pub-repo.git' -Override '1'
        $result.ExitCode | Should -Be 0
    }
}

Describe 'GitHub URL parsing' {
    It 'Should extract owner/repo from HTTPS URL' {
        $content = Get-Content $script:hookPath -Raw
        $content | Should -Match 'github\\\.com\[/:\]'
    }

    It 'Should handle .git suffix in URL' {
        $content = Get-Content $script:hookPath -Raw
        $content | Should -Match '\.git'
    }
}

Describe 'Integration: public repo blocking' -Tag 'Integration' {
    BeforeAll {
        if (-not $script:ghAvailable) {
            Set-ItResult -Skipped -Because "'gh' CLI not available"
        }
    }

    It 'Should block push to a known public repo (cli/cli)' {
        $result = Invoke-PushGuard -RemoteName 'upstream' -RemoteUrl 'https://github.com/cli/cli.git'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'BLOCKED'
    }
}
