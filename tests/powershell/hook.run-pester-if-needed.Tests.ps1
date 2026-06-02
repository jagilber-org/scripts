<#
.SYNOPSIS
    Pester tests for hooks/run-pester-if-needed.ps1
#>

BeforeAll {
    $script:hookPath = Join-Path $PSScriptRoot '..\..\hooks\run-pester-if-needed.ps1'

    function Invoke-RunPesterIfNeeded {
        param(
            [string]$RepositoryPath,
            [string[]]$Files = @()
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'pwsh'
        $startInfo.WorkingDirectory = $RepositoryPath
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
            Output = $combinedOutput -join "`n"
            ExitCode = $process.ExitCode
        }
    }

    function New-HookTestRepository {
        $repoPath = Join-Path ([System.IO.Path]::GetTempPath()) "pester-hook-run-pester-$(Get-Random)"
        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null

        git -C $repoPath init | Out-Null
        git -C $repoPath config user.name 'Test User'
        git -C $repoPath config user.email 'test@example.com'

        return $repoPath
    }
}

Describe 'Script Validation' {
    It 'Should exist at hooks/run-pester-if-needed.ps1' {
        Test-Path $script:hookPath | Should -Be $true
    }

    It 'Should have no parse errors' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:hookPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Pester gating behavior' {
    It 'Should skip when only non-script files are staged' {
        $repoPath = New-HookTestRepository
        try {
            'hello' | Set-Content (Join-Path $repoPath 'README.md')
            git -C $repoPath add README.md

            $result = Invoke-RunPesterIfNeeded -RepositoryPath $repoPath
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'Skipping Pester'
        }
        finally {
            Remove-Item $repoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should skip when staged PowerShell changes are whitespace-only' {
        $repoPath = New-HookTestRepository
        try {
            New-Item -ItemType Directory -Path (Join-Path $repoPath 'powershell\utilities') -Force | Out-Null
            @'
function Test-Sample {
    Write-Host "sample"
}
'@ | Set-Content (Join-Path $repoPath 'powershell\utilities\Test-Sample.ps1')

            git -C $repoPath add .
            git -C $repoPath commit -m 'baseline' | Out-Null

            @'
function Test-Sample {
    Write-Host    "sample"
}
'@ | Set-Content (Join-Path $repoPath 'powershell\utilities\Test-Sample.ps1')

            git -C $repoPath add powershell/utilities/Test-Sample.ps1

            $result = Invoke-RunPesterIfNeeded -RepositoryPath $repoPath
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'Only whitespace changes detected'
        }
        finally {
            Remove-Item $repoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should run Pester when substantive script changes are staged' {
        $repoPath = New-HookTestRepository
        try {
            New-Item -ItemType Directory -Path (Join-Path $repoPath 'powershell\utilities') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repoPath 'tests\powershell') -Force | Out-Null

            @'
function Test-Sample {
    Write-Host "sample"
}
'@ | Set-Content (Join-Path $repoPath 'powershell\utilities\Test-Sample.ps1')

            @'
Describe "placeholder" {
    It "passes" {
        $true | Should -BeTrue
    }
}
'@ | Set-Content (Join-Path $repoPath 'tests\powershell\placeholder.Tests.ps1')

            git -C $repoPath add .
            git -C $repoPath commit -m 'baseline' | Out-Null

            @'
function Test-Sample {
    Write-Host "changed"
}
'@ | Set-Content (Join-Path $repoPath 'powershell\utilities\Test-Sample.ps1')

            git -C $repoPath add powershell/utilities/Test-Sample.ps1

            $result = Invoke-RunPesterIfNeeded -RepositoryPath $repoPath
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'Running full Pester suite'
        }
        finally {
            Remove-Item $repoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should run focused hook tests when only hook files change' {
        $repoPath = New-HookTestRepository
        try {
            New-Item -ItemType Directory -Path (Join-Path $repoPath 'hooks') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $repoPath 'tests\powershell') -Force | Out-Null

            @'
Write-Host "baseline"
'@ | Set-Content (Join-Path $repoPath 'hooks\check-env-leaks.ps1')

            @'
Describe "placeholder" {
    It "passes" {
        $true | Should -BeTrue
    }
}
'@ | Set-Content (Join-Path $repoPath 'tests\powershell\hook.check-env-leaks.Tests.ps1')

            git -C $repoPath add .
            git -C $repoPath commit -m 'baseline' | Out-Null

            @'
Write-Host "changed"
'@ | Set-Content (Join-Path $repoPath 'hooks\check-env-leaks.ps1')

            git -C $repoPath add hooks/check-env-leaks.ps1

            $result = Invoke-RunPesterIfNeeded -RepositoryPath $repoPath
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'Running focused Pester tests'
            $result.Output | Should -Not -Match 'Running full Pester suite'
        }
        finally {
            Remove-Item $repoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
