<#
.SYNOPSIS
    Pester tests for hooks/check-env-leaks.ps1
.NOTES
    Requires: Pester 5.x+
#>

BeforeAll {
    $script:hookPath = Join-Path $PSScriptRoot '..\..\hooks\check-env-leaks.ps1'

    function Invoke-CheckEnvLeaks {
        param(
            [string[]]$Files,
            [hashtable]$Environment = @{}
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'pwsh'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        [void]$startInfo.ArgumentList.Add('-NoProfile')
        [void]$startInfo.ArgumentList.Add('-NonInteractive')
        [void]$startInfo.ArgumentList.Add('-File')
        [void]$startInfo.ArgumentList.Add($script:hookPath)

        foreach ($file in $Files) {
            [void]$startInfo.ArgumentList.Add($file)
        }

        $startInfo.Environment['PATH'] = $env:PATH
        $startInfo.Environment['TEST_SAFE_VALUE'] = 'public'
        $startInfo.Environment['GITHUB_TOKEN'] = 'ghp_test_secret_value_123456789'
        $startInfo.Environment['AZURE_CLIENT_SECRET'] = 'azure_secret_value_123456789'

        foreach ($pair in $Environment.GetEnumerator()) {
            $startInfo.Environment[$pair.Key] = [string]$pair.Value
        }

        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $combinedOutput = @($stdout, $stderr) | Where-Object { $_ }
        [PSCustomObject]@{
            Output   = $combinedOutput -join "`n"
            ExitCode = $process.ExitCode
        }
    }
}

Describe 'Script Validation' {
    It 'Should exist at hooks/check-env-leaks.ps1' {
        Test-Path $script:hookPath | Should -Be $true
    }

    It 'Should have no parse errors' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Environment value leak detection' {
    BeforeAll {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-check-env-leaks-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should flag an exact sensitive environment value leak' {
        $f = Join-Path $script:tmpDir 'leak.ps1'
        '$token = "ghp_test_secret_value_123456789"' | Set-Content $f
        $result = Invoke-CheckEnvLeaks -Files $f
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'GITHUB_TOKEN'
        $result.Output | Should -Not -Match 'ghp_test_secret_value_123456789'
    }

    It 'Should ignore clean files' {
        $f = Join-Path $script:tmpDir 'clean.ps1'
        'Write-Host "safe"' | Set-Content $f
        $result = Invoke-CheckEnvLeaks -Files $f
        $result.ExitCode | Should -Be 0
    }

    It 'Should ignore short or allowlisted environment values' {
        $f = Join-Path $script:tmpDir 'allowlisted.ps1'
        '$branch = "public"' | Set-Content $f
        $result = Invoke-CheckEnvLeaks -Files $f -Environment @{ SAFE_BRANCH = 'public' }
        $result.ExitCode | Should -Be 0
    }

    It 'Should ignore short lowercase slug values from sensitive env vars' {
        $f = Join-Path $script:tmpDir 'slug.ps1'
        'Write-Host "jagilber"' | Set-Content $f
        $result = Invoke-CheckEnvLeaks -Files $f -Environment @{ KEY_VAULT = 'jagilber' }
        $result.ExitCode | Should -Be 0
    }

    It 'Should report multiple leaked variables by name' {
        $f = Join-Path $script:tmpDir 'multi.ps1'
        @'
$one = "ghp_test_secret_value_123456789"
$two = "azure_secret_value_123456789"
'@ | Set-Content $f
        $result = Invoke-CheckEnvLeaks -Files $f
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'GITHUB_TOKEN'
        $result.Output | Should -Match 'AZURE_CLIENT_SECRET'
        $result.Output | Should -Not -Match 'azure_secret_value_123456789'
    }
}
