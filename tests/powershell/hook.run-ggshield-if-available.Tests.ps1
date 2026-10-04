<#
.SYNOPSIS
    Pester tests for hooks/run-ggshield-if-available.ps1.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Justification = 'This test-only fixture helper writes exclusively under Pester TestDrive.'
)]
param()

BeforeAll {
    $script:hookPath = Join-Path $PSScriptRoot '..\..\hooks\run-ggshield-if-available.ps1'

    function Invoke-GgshieldHookTest {
        param(
            [Parameter(Mandatory)]
            [string]$PathValue,

            [string]$Mode
        )

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'pwsh'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        [void]$startInfo.ArgumentList.Add('-NoProfile')
        [void]$startInfo.ArgumentList.Add('-NonInteractive')
        [void]$startInfo.ArgumentList.Add('-File')
        [void]$startInfo.ArgumentList.Add($script:hookPath)
        $startInfo.Environment['PATH'] = $PathValue
        $startInfo.Environment['GG_TEST_MODE'] = $Mode

        $process = [Diagnostics.Process]::Start($startInfo)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = @($stdout, $stderr) -join "`n"
        }
    }

    function New-FakeGgshieldDirectory {
        $directory = Join-Path $TestDrive "ggshield-$(Get-Random)"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        @'
@echo off
        if "%1"=="quota" goto quota
        if "%1"=="secret" goto secret
exit /b 3

        :quota
        if "%GG_TEST_MODE%"=="auth-fail" exit /b 2
        if "%GG_TEST_MODE%"=="zero" echo Quota available: 0
        if "%GG_TEST_MODE%"=="available" echo Quota available: 5
        if "%GG_TEST_MODE%"=="finding" echo Quota available: 5
        exit /b 0

        :secret
        echo scan invoked
        if "%GG_TEST_MODE%"=="finding" exit /b 1
        exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $directory 'ggshield.cmd') -Encoding ascii
        return $directory
    }
}

Describe 'Script Validation' {
    It 'Should exist at hooks/run-ggshield-if-available.ps1' {
        Test-Path -LiteralPath $script:hookPath | Should -BeTrue
    }

    It 'Should have no parse errors' {
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath,
            [ref]$null,
            [ref]$parseErrors
        )
        $parseErrors.Count | Should -Be 0
    }
}

Describe 'GitGuardian availability gate' {
    It 'Should continue when ggshield is not installed' {
        $result = Invoke-GgshieldHookTest -PathValue "$env:SystemRoot\System32"

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'ggshield is not installed'
    }

    It 'Should continue when authentication or quota lookup fails' {
        $fakeDirectory = New-FakeGgshieldDirectory
        $result = Invoke-GgshieldHookTest `
            -PathValue "$fakeDirectory;$env:SystemRoot\System32" `
            -Mode 'auth-fail'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'authentication or quota lookup failed'
    }

    It 'Should continue when no API quota remains' {
        $fakeDirectory = New-FakeGgshieldDirectory
        $result = Invoke-GgshieldHookTest `
            -PathValue "$fakeDirectory;$env:SystemRoot\System32" `
            -Mode 'zero'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'no remaining API quota'
        $result.Output | Should -Not -Match 'scan invoked'
    }

    It 'Should require the scan when GitGuardian is available' {
        $fakeDirectory = New-FakeGgshieldDirectory
        $result = Invoke-GgshieldHookTest `
            -PathValue "$fakeDirectory;$env:SystemRoot\System32" `
            -Mode 'available'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'GitGuardian available'
        $result.Output | Should -Match 'scan invoked'
    }

    It 'Should propagate a finding from an available scan' {
        $fakeDirectory = New-FakeGgshieldDirectory
        $result = Invoke-GgshieldHookTest `
            -PathValue "$fakeDirectory;$env:SystemRoot\System32" `
            -Mode 'finding'

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'scan invoked'
    }
}
