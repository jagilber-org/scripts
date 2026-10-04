<#
.SYNOPSIS
    Pester tests for hooks/check-pii.ps1
.NOTES
    Requires: Pester 5.x+
#>

BeforeAll {
    $script:hookPath  = Join-Path $PSScriptRoot '..\..\hooks\check-pii.ps1'
    $script:allowlist = Join-Path $PSScriptRoot '..\..' '.pii-allowlist'

    function Invoke-CheckPii {
        param([string[]]$Files)

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
    It 'Should exist at hooks/check-pii.ps1' {
        Test-Path $script:hookPath | Should -Be $true
    }

    It 'Should have no parse errors' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Should have a .pii-allowlist file at repo root' {
        Test-Path $script:allowlist | Should -Be $true
    }
}

Describe 'PII detection' {
    BeforeAll {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-check-pii-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Should detect PII' {
        It 'Should flag an email address' {
            $f = Join-Path $script:tmpDir 'email.ps1'
            '$contact = "john.doe@fabrikam.io"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'Email address'
        }

        It 'Should flag a US phone number' {
            $f = Join-Path $script:tmpDir 'phone.ps1'
            '$phone = "555-246-8100"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'phone'
        }

        It 'Should flag an SSN' {
            $f = Join-Path $script:tmpDir 'ssn.ps1'
            '$ssn = "321-54-9876"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'SSN'
        }

        It 'Should flag a public IPv4 address' {
            $f = Join-Path $script:tmpDir 'ip.ps1'
            '$server = "44.55.66.77"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'IPv4'
        }
    }

    Context 'Should not flag private/safe values' {
        It 'Should allow private RFC1918 address 10.x.x.x' {
            $f = Join-Path $script:tmpDir 'private-ip.ps1'
            '$server = "10.0.0.1"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should allow loopback 127.0.0.1' {
            $f = Join-Path $script:tmpDir 'loopback.ps1'
            '$local = "127.0.0.1"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should allow a clean file with no PII' {
            $f = Join-Path $script:tmpDir 'clean.ps1'
            'Write-Host "Hello, World!"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should skip lines with # pii-allowlist marker' {
            $f = Join-Path $script:tmpDir 'inline-allow.ps1'
            '$email = "real.person@company.com" # pii-allowlist' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should allow address in .pii-allowlist (169.254.169.254)' {
            $f = Join-Path $script:tmpDir 'metadata.ps1'
            '$url = "https://169.254.169.254/metadata"' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }

        It 'Should no longer skip testResults.xml (removed from skip list)' {
            $f = Join-Path $script:tmpDir 'testResults.xml'
            '<test-results version="2.5.8.0" />' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            # testResults.xml is in .gitignore and should never be committed.
            # The PII hook no longer skips it — any PII inside will be flagged.
            $result.ExitCode | Should -Be 1
        }

        It 'Should skip the detect-secrets baseline file' {
            $f = Join-Path $script:tmpDir '.secrets.baseline'
            '{"hashed_secret":"2a0f32307eafe99b530cd950b46cb36727401531"}' | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'Multiple PII in one file' {
        It 'Should report all findings when multiple PII present' {
            $f = Join-Path $script:tmpDir 'multi-pii.ps1'
            @'
$email = "test@fabrikam.io"
$ssn = "321-54-9876"
'@ | Set-Content $f
            $result = Invoke-CheckPii -Files $f
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'Email address'
            $result.Output | Should -Match 'SSN'
        }
    }
}
