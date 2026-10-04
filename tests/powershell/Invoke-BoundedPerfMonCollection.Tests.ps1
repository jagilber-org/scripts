[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'scriptContent',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'scriptAst',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'command',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
param()

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\powershell\diagnostics\Invoke-BoundedPerfMonCollection.ps1'
    $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
    $parseErrors = $null
    $scriptAst = [Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$null,
        [ref]$parseErrors
    )
    $command = Get-Command -Name $scriptPath
}

Describe 'Invoke-BoundedPerfMonCollection' {
    Context 'Script Validation' {
        It 'Should exist' {
            Test-Path -LiteralPath $scriptPath | Should -BeTrue
        }

        It 'Should have valid PowerShell syntax' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Should have a synopsis and description' {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should use an approved PowerShell verb' {
            (Get-Verb -Verb Invoke).Verb | Should -Contain 'Invoke'
        }

        It 'Should include version and changelog metadata' {
            $scriptContent | Should -Match '(?m)^\s+Version\s+:\s+2\.1\.0\r?$'
            $scriptContent | Should -Match '(?m)^\s+Changelog\s+:'
        }
    }

    Context 'Local-Only Interface' {
        It 'Should expose only local collector actions' {
            $validateSet = $command.Parameters['Action'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }

            $validateSet.ValidValues | Should -Be @('Start', 'Status', 'Stop', 'Cleanup')
        }

        It 'Should not expose remote or dynamic-counter parameters' {
            $command.Parameters.Keys | Should -Not -Contain 'ComputerName'
            $command.Parameters.Keys | Should -Not -Contain 'AdditionalCounterRegex'
            $command.Parameters.Keys | Should -Not -Contain 'Note'
        }

        It 'Should not contain remote collection or packaging code' {
            $scriptContent | Should -Not -Match 'Get-Counter\s+-ComputerName'
            $scriptContent | Should -Not -Match 'Get-TargetCoverage'
            $scriptContent | Should -Not -Match 'Compress-Archive'
            $scriptContent | Should -Not -Match "'-u'"
        }

        It 'Should retain recovery state when BLG validation fails' {
            $scriptContent | Should -Match '\$collectorAbsent -and \(\$CleanupOnly -or \$errors\.Count -eq 0\)'
            $scriptContent | Should -Match 'Recovery state was retained'
        }
    }

    Context 'Runtime and Bounds' {
        It 'Should require 64-bit Windows PowerShell 5.1' {
            $scriptContent | Should -Match '(?m)^#requires -Version 5\.1\r?$'
            $scriptContent | Should -Match "PSEdition -ne 'Desktop'"
            $scriptContent | Should -Match 'Is64BitProcess'
        }

        It 'Should retain the complete fixed diagnostic counter set' {
            $counterFunction = $scriptAst.Find(
                {
                    param($node)
                    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                        $node.Name -eq 'Get-BaseCounter'
                },
                $true
            )
            $counterLiterals = @($counterFunction.FindAll(
                {
                    param($node)
                    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
                        $node.Value.StartsWith('\')
                },
                $true
            ))

            $counterLiterals.Count | Should -Be 50
            $counterLiterals.Value | Should -Contain '\Memory\Page Faults/sec'
            $counterLiterals.Value | Should -Contain '\Process(*)\Working Set - Private'
            $counterLiterals.Value | Should -Contain '\Process(*)\Page Faults/sec'
            $counterLiterals.Value | Should -Contain '\Process(*)\IO Other Bytes/sec'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Avg. Disk sec/Read'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Current Disk Queue Length'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Disk Reads/sec'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Disk Writes/sec'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Disk Read Bytes/sec'
            $counterLiterals.Value | Should -Contain '\PhysicalDisk(*)\Disk Write Bytes/sec'
            $counterLiterals.Value | Should -Contain '\LogicalDisk(*)\Free Megabytes'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Bytes Total/sec'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Current Bandwidth'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Packets Received Errors'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Packets Outbound Errors'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Packets Received Discarded'
            $counterLiterals.Value | Should -Contain '\Network Interface(*)\Packets Outbound Discarded'
            $counterLiterals.Value | Should -Contain '\TCPv4\Segments Retransmitted/sec'
        }

        It 'Should pass all three independent limits to Logman' {
            $scriptContent | Should -Match "'-f', 'bincirc', '-max'"
            $scriptContent | Should -Match '''-si'', \$interval, ''-rf'', \$duration'
            $scriptContent | Should -Match '''-sc'', \[string\]\$maximumSamples'
        }

        It 'Should reject unsafe parameter values before execution' {
            { & $scriptPath -Action Start -DurationMinutes 61 } | Should -Throw
            { & $scriptPath -Action Start -SampleIntervalSeconds 1 } | Should -Throw
            { & $scriptPath -Action Start -MaximumLogMB 2048 } | Should -Throw
            { & $scriptPath -Action Start -OutputRoot 'relative\path' } | Should -Throw
            { & $scriptPath -Action Start -OutputRoot 'C:\Path With Spaces' } | Should -Throw
        }

        It 'Should reject PowerShell 7 with a direct instruction' -Skip:($PSVersionTable.PSEdition -eq 'Desktop') {
            { & $scriptPath -Action Status } |
                Should -Throw '*requires Windows PowerShell 5.1*'
        }

        It 'Should require existing state for status in Windows PowerShell 5.1' `
            -Skip:($env:OS -ne 'Windows_NT') {
            $outputRoot = Join-Path $TestDrive 'MissingState'

            $output = & powershell.exe -NoLogo -NoProfile -NonInteractive `
                -File $scriptPath -Action Status -OutputRoot $outputRoot 2>&1 | Out-String

            $LASTEXITCODE | Should -Not -Be 0
            $output | Should -Match 'No collection state was found'
        }

        It 'Should reject incomplete recovery state in Windows PowerShell 5.1' `
            -Skip:($env:OS -ne 'Windows_NT') {
            $outputRoot = Join-Path $TestDrive 'InvalidState'
            New-Item -ItemType Directory -Path $outputRoot | Out-Null
            '{}' | Set-Content -LiteralPath (Join-Path $outputRoot 'Bounded-PerfMon-Current.json')

            $output = & powershell.exe -NoLogo -NoProfile -NonInteractive `
                -File $scriptPath -Action Status -OutputRoot $outputRoot 2>&1 | Out-String

            $LASTEXITCODE | Should -Not -Be 0
            $output | Should -Match 'Collection state is incomplete or unsupported'
        }
    }

    Context 'Lifecycle Integration' -Tag 'Integration' {
        It 'Should create, stop, validate, and remove a local collector' `
            -Skip:($env:RUN_BOUNDED_PERFMON_INTEGRATION -ne '1' -or
                $PSVersionTable.PSEdition -ne 'Desktop') {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Set-ItResult -Skipped -Because 'The collector lifecycle requires elevation.'
                return
            }

            $outputRoot = Join-Path $env:TEMP "BoundedPerfMonCollection-$PID"
            $waitHandle = New-Object Threading.ManualResetEventSlim($false)
            try {
                $started = & $scriptPath -Action Start -OutputRoot $outputRoot `
                    -DurationMinutes 1 -SampleIntervalSeconds 2 `
                    -MaximumLogMB 100 -MinimumFreeMB 2048
                $started.Status | Should -BeIn @('Running', 'Pending')

                $waitHandle.Wait([TimeSpan]::FromSeconds(10))
                $result = & $scriptPath -Action Stop -OutputRoot $outputRoot

                $result.Validation | Should -Be 'PASS'
                $result.CollectorPresent | Should -BeFalse
                $result.SampleCount | Should -BeGreaterThan 0
                Test-Path -LiteralPath $result.BlgPath | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $outputRoot 'Bounded-PerfMon-Current.json') |
                    Should -BeFalse
                Test-Path -LiteralPath "$($result.OutputDirectory).zip" | Should -BeFalse
            }
            finally {
                $waitHandle.Dispose()
                if (Test-Path -LiteralPath (Join-Path $outputRoot 'Bounded-PerfMon-Current.json')) {
                    & $scriptPath -Action Cleanup -OutputRoot $outputRoot | Out-Null
                }
                Remove-Item -LiteralPath $outputRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
