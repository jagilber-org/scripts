[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'scriptContent',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'command',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'meta',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'json',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'csv',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'blgMeta',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'mixedMeta',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    'mixedJson',
    Justification = 'Pester BeforeAll variables are consumed by It blocks at runtime.'
)]
param()

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\powershell\diagnostics\Export-PerfCounterHelp.ps1'
    $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
    $parseErrors = $null
    $scriptAst = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
    $command = Get-Command -Name $scriptPath

    # load the path parser without running the script
    $fn = $scriptAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Split-CounterPath'
        }, $true) | Select-Object -First 1
    . ([scriptblock]::Create($fn.Extent.Text))
}

Describe 'Export-PerfCounterHelp' {
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
            (Get-Verb -Verb Export).Verb | Should -Contain 'Export'
        }

        It 'Should include version and changelog metadata' {
            $scriptContent | Should -Match '(?m)^\s+Version\s+:\s+1\.0\.0\r?$'
            $scriptContent | Should -Match '(?m)^\s+Changelog\s+:'
        }

        It 'Should restrict Format to Csv, Json, Markdown' {
            $validateSet = $command.Parameters['Format'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Be @('Csv', 'Json', 'Markdown')
        }
    }

    Context 'Parameter Validation' {
        It 'Rejects a computer name with path or shell characters' {
            $invalidName = 'bad\name;x'
            { & $scriptPath -ComputerName $invalidName -OutputDirectory $TestDrive } | Should -Throw -ExceptionType ([Management.Automation.ParameterBindingException])
        }

        It 'Rejects a BlgPath that does not exist' {
            { & $scriptPath -BlgPath (Join-Path $TestDrive 'missing.blg') -OutputDirectory $TestDrive } | Should -Throw -ExceptionType ([Management.Automation.ParameterBindingException])
        }

        It 'Rejects an unknown Format' {
            { & $scriptPath -Format 'Xml' -OutputDirectory $TestDrive } | Should -Throw -ExceptionType ([Management.Automation.ParameterBindingException])
        }
    }

    Context 'Split-CounterPath' {
        It 'Parses a single-instance local path' {
            $p = Split-CounterPath '\Memory\Available MBytes'
            $p.Object | Should -Be 'Memory'
            $p.Instance | Should -BeNullOrEmpty
            $p.Counter | Should -Be 'Available MBytes'
        }

        It 'Parses a machine-qualified multi-instance path' {
            $p = Split-CounterPath '\\SERVER01\Process(svchost#1)\% Processor Time'
            $p.Object | Should -Be 'Process'
            $p.Instance | Should -Be 'svchost#1'
            $p.Counter | Should -Be '% Processor Time'
        }

        It 'Keeps parentheses inside instance names' {
            $p = Split-CounterPath '\\SERVER01\Network Interface(Adapter (Ethernet) 2)\Bytes Total/sec'
            $p.Object | Should -Be 'Network Interface'
            $p.Instance | Should -Be 'Adapter (Ethernet) 2'
            $p.Counter | Should -Be 'Bytes Total/sec'
        }

        It 'Parses a wildcard instance path' {
            (Split-CounterPath '\Processor Information(*)\% Processor Time').Instance | Should -Be '*'
        }

        It 'Returns null for a non-counter string' {
            Split-CounterPath 'not a counter path' | Should -BeNullOrEmpty
        }
    }

    Context 'Local dump (Windows)' -Tag 'Integration' -Skip:(-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        BeforeAll {
            # Arrange + Act: read one well-known counter set through PDH
            $outDir = Join-Path $TestDrive 'dump'
            $meta = & $scriptPath -CounterSet 'Memory' -OutputDirectory $outDir -Format Json, Csv, Markdown 6>$null
            $json = Get-Content (Get-ChildItem $outDir -Filter *.json).FullName -Raw | ConvertFrom-Json
            $csv = Import-Csv (Get-ChildItem $outDir -Filter *.csv).FullName
        }

        It 'Writes one file per format' {
            (Get-ChildItem $outDir -File).Extension | Sort-Object | Should -Be @('.csv', '.json', '.md')
        }

        It 'Reads the Memory counter set with help text' {
            $meta.CounterSetCount | Should -Be 1
            $meta.CounterCount | Should -BeGreaterThan 10
            $meta.FailedCount | Should -Be 0
            ($csv | Where-Object Counter -eq 'Available MBytes').Help | Should -Not -BeNullOrEmpty
        }

        It 'Decodes every counter type' {
            $csv | Where-Object CounterType -eq 'UNKNOWN' | Should -BeNullOrEmpty
            ($csv | Where-Object Counter -eq 'Page Faults/sec').ValueKind | Should -Be 'rate per second'
        }

        It 'Records provenance metadata in the JSON' {
            $json.Metadata.Source | Should -Match 'PdhGetCounterInfo'
            $json.Metadata.OsBuild | Should -Not -BeNullOrEmpty
        }

        It 'Throws when no counter set matches' {
            { & $scriptPath -CounterSet 'NoSuchCounterSet-Synthetic' -OutputDirectory (Join-Path $TestDrive 'none') } | Should -Throw
        }
    }

    Context 'BLG filter (Windows)' -Tag 'Integration' -Skip:(-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        BeforeAll {
            # Arrange: synthetic one-counter log; Act: dump only what the log contains
            $blg = Join-Path $TestDrive 'synthetic.blg'
            & typeperf.exe '\Memory\% Committed Bytes In Use' -sc 2 -si 1 -f BIN -o $blg -y | Out-Null
            $blgMeta = & $scriptPath -BlgPath $blg -OutputDirectory (Join-Path $TestDrive 'blg') -Format Json 6>$null
        }

        It 'Limits output to the counters in the log' {
            Test-Path $blg | Should -BeTrue
            $blgMeta.CounterCount | Should -Be 1
            $blgMeta.MissingLocally | Should -Be 0
        }
    }

    Context 'Log counters not installed locally (Windows)' -Tag 'Integration' -Skip:(-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        BeforeAll {
            # Arrange: synthetic PDH CSV logs from a fictitious machine with an uninstalled counter set
            $header = '"(PDH-CSV 4.0) (Coordinated Universal Time)(0)"'
            $rows = '"09/29/2026 12:00:00.000","1","1024"', '"09/29/2026 12:00:01.000","2","1023"'
            $mixedLog = Join-Path $TestDrive 'mixed.csv'
            @("$header,""\\SYNTH01\Synthetic Missing Set\Widgets/sec"",""\\SYNTH01\Memory\Available MBytes""") + $rows |
                Set-Content $mixedLog -Encoding ascii
            $missingOnlyLog = Join-Path $TestDrive 'missing-only.csv'
            @("$header,""\\SYNTH01\Synthetic Missing Set\Widgets/sec""", '"09/29/2026 12:00:00.000","1"', '"09/29/2026 12:00:01.000","2"') |
                Set-Content $missingOnlyLog -Encoding ascii

            # Act
            $mixedDir = Join-Path $TestDrive 'mixed'
            $mixedMeta = & $scriptPath -BlgPath $mixedLog -OutputDirectory $mixedDir -Format Json 6>$null 3>$null
            $mixedJson = Get-Content (Get-ChildItem $mixedDir -Filter *.json).FullName -Raw | ConvertFrom-Json
        }

        It 'Returns installed counters and reports the rest as missing' {
            $mixedMeta.CounterCount | Should -Be 1
            $mixedMeta.MissingLocally | Should -Be 1
            $mixedJson.MissingLocally | Should -Contain '\\SYNTH01\Synthetic Missing Set\Widgets/sec'
        }

        It 'Does not throw when no counter in the log is installed locally' {
            $meta = & $scriptPath -BlgPath $missingOnlyLog -OutputDirectory (Join-Path $TestDrive 'missing') -Format Json 6>$null 3>$null
            $meta.CounterCount | Should -Be 0
            $meta.MissingLocally | Should -Be 1
        }
    }
}
