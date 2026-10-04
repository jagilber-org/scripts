BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\powershell\diagnostics\Start-RealtimeTrace.ps1'
}

Describe 'Start-RealtimeTrace' {
    Context 'Script Validation' {
        It 'Should exist' {
            Test-Path -LiteralPath $scriptPath | Should -BeTrue
        }

        It 'Should have valid PowerShell syntax' {
            $parseErrors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content -LiteralPath $scriptPath -Raw),
                [ref]$parseErrors
            )
            $parseErrors.Count | Should -Be 0
        }

        It 'Should have a synopsis' {
            (Get-Help $scriptPath).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            (Get-Help $scriptPath).Description | Should -Not -BeNullOrEmpty
        }

        It 'Should use an approved PowerShell verb' {
            (Get-Verb -Verb Start).Verb | Should -Contain 'Start'
        }

        It 'Should include version and changelog metadata' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match '(?m)^\s+Version\s+:\s+\d+\.\d+\.\d+\r?$'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match '(?m)^\s+Changelog\s+:'
        }
    }

    Context 'Generic Trace Configuration' {
        It 'Should expose the realtime trace parameters' {
            $parameters = (Get-Command $scriptPath).Parameters.Keys
            foreach ($parameterName in @('TraceFilePath', 'Filters', 'TraceProviders', 'OnMatch', 'ShowMatch', 'Remove', 'ListProviders', 'ProcessId', 'ConfigPath', 'ExportConfigPath')) {
                $parameters | Should -Contain $parameterName
            }
        }

        It 'Should use generic Windows providers by default' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Microsoft-Windows-TCPIP'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Microsoft-Windows-DNS-Client'
        }

        It 'Should show every event by default without console filters' {
            $command = Get-Command $scriptPath
            $command.Parameters['Filters'].Attributes |
                Where-Object { $PSItem -is [Management.Automation.AllowEmptyCollectionAttribute] } |
                Should -Not -BeNullOrEmpty
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match "\[string\[\]\]\`$Filters = @\(\)"
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Console output: all events \(no filters configured\)\.'
        }

        It 'Should not have a Service Fabric dependency' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Not -Match 'Microsoft-ServiceFabric'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Not -Match '\\service-fabric\\'
        }

        It 'Should not execute match actions from strings' {
            $restrictedCommandName = @('Invoke', 'Expression') -join '-'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Not -Match ([regex]::Escape($restrictedCommandName))
        }
    }

    Context 'Provider Wildcards' -Skip:($env:OS -ne 'Windows_NT') {
        It 'Should filter registered providers with a wildcard' {
            $providers = @(
                & $scriptPath -ListProviders -TraceProviders 'Microsoft-Windows-DNS-*'
            )

            $providers.Count | Should -BeGreaterThan 0
            $providers.Provider | Should -Contain 'Microsoft-Windows-DNS-Client'
            $providers.TraceCapable | Should -Not -Contain $false
            $providers.Provider | ForEach-Object {
                $PSItem | Should -BeLike 'Microsoft-Windows-DNS-*'
            }
        }

        It 'Should include matching classic event sources in global listings' {
            if ($null -eq (Get-WinEvent -ListProvider 'rhproxy' -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'The rhproxy event source is not installed.'
                return
            }

            $providers = @(
                & $scriptPath -ListProviders -TraceProviders '*rh*'
            )

            $providers.Provider | Should -Contain 'rhproxy'
            $rhproxy = $providers | Where-Object Provider -EQ 'rhproxy'
            ($rhproxy.TraceCapable -eq $false) | Should -BeFalse
            $rhproxy.DiscoverySource | Should -BeIn @('Logman', 'EventLog')
        }

        It 'Should support wildcard filtering for process-scoped providers' {
            $providers = @(
                & $scriptPath -ListProviders -ProcessId $PID -TraceProviders 'Microsoft-Windows-*'
            )

            $providers.Count | Should -BeGreaterThan 0
            $providers.TraceCapable | Should -Not -Contain $false
            $providers.Provider | ForEach-Object {
                $PSItem | Should -BeLike 'Microsoft-Windows-*'
            }
        }

        It 'Should use all process providers when tracing by process ID alone' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match '\$ProcessId -gt 0 -and -not \$traceProvidersSpecified'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Get-RealtimeTraceProvider -Id \$ProcessId -NamePattern \$providerPatterns'
        }

        It 'Should tolerate partial wildcard misses and reject an empty result set' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match '-AllowPartialMatch'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'None of the provider patterns matched'
        }

        It 'Should preserve effective arguments when restarting elevated' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Match 'Start-Process .* -Verb RunAs'
            $content |
                Should -Match 'Export-RealtimeTraceConfiguration -Path \$temporaryConfigPath'
            $content | Should -Match '\$escapedScriptPath'
            $content | Should -Match '\$escapedConfigPath'
        }

        It 'Should print resolved providers before tracing' {
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Write-RealtimeTracePlan -Provider \$resolvedProviderRecords'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Trace is running\. Press Ctrl\+C to stop'
            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Console output is limited to matches for:'
        }

        It 'Should return no rows when a listing wildcard has no matches' {
            $providers = @(
                & $scriptPath -ListProviders -TraceProviders 'Provider-That-Does-Not-Exist-*'
            )

            $providers.Count | Should -Be 0
        }

        It 'Should resolve provider wildcards in the tracing path' {
            $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
            $isAdministrator = $currentPrincipal.IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
            if (-not $isAdministrator) {
                Set-ItResult -Skipped -Because 'Packet Monitor tracing requires elevation.'
                return
            }

            {
                & $scriptPath -TraceProviders @(
                    'Microsoft-Windows-DNS-*',
                    'Provider-That-Does-Not-Exist-*'
                ) -WhatIf
            } | Should -Not -Throw

            Get-Content -LiteralPath $scriptPath -Raw |
                Should -Match 'Start-PktMonRealtimeTrace -Provider \$resolvedProviders'
        }
    }

    Context 'JSON Configuration' {
        It 'Should export every trace argument' {
            $configPath = Join-Path $TestDrive 'trace-config.json'
            $onMatch = { param($Match, $Line, $Count) $Count | Out-Null }

            & $scriptPath -TraceFilePath (Join-Path $TestDrive 'trace.log') `
                -Filters 'warning', 'error' `
                -TraceProviders 'Microsoft-Windows-DNS-*' `
                -OnMatch $onMatch -ShowMatch:$false -Remove -ListProviders `
                -ProcessId 42 -ExportConfigPath $configPath

            $configuration = Get-Content -LiteralPath $configPath -Raw |
                ConvertFrom-Json
            $configuration.PSObject.Properties.Name | Should -Be @(
                'TraceFilePath',
                'Filters',
                'TraceProviders',
                'OnMatch',
                'ShowMatch',
                'Remove',
                'ListProviders',
                'ProcessId'
            )
            $configuration.Filters | Should -Be @('warning', 'error')
            $configuration.TraceProviders | Should -Be @('Microsoft-Windows-DNS-*')
            $configuration.OnMatch | Should -Match '\$Count'
            $configuration.ShowMatch | Should -BeFalse
            $configuration.Remove | Should -BeTrue
            $configuration.ListProviders | Should -BeTrue
            $configuration.ProcessId | Should -Be 42
        }

        It 'Should round-trip an empty filter array' {
            $sourcePath = Join-Path $TestDrive 'unfiltered-config.json'
            $effectivePath = Join-Path $TestDrive 'unfiltered-effective-config.json'

            & $scriptPath -ExportConfigPath $sourcePath
            $sourceConfiguration = Get-Content -LiteralPath $sourcePath -Raw |
                ConvertFrom-Json
            @($sourceConfiguration.Filters).Count | Should -Be 0

            & $scriptPath -ConfigPath $sourcePath `
                -ExportConfigPath $effectivePath
            $effectiveConfiguration = Get-Content -LiteralPath $effectivePath -Raw |
                ConvertFrom-Json
            @($effectiveConfiguration.Filters).Count | Should -Be 0
        }

        It 'Should import JSON arguments and honor command-line precedence' {
            $sourcePath = Join-Path $TestDrive 'source-config.json'
            $effectivePath = Join-Path $TestDrive 'effective-config.json'
            [ordered]@{
                TraceFilePath  = Join-Path $TestDrive 'configured.log'
                Filters        = @('configured')
                TraceProviders = @('Microsoft-Windows-DNS-*')
                OnMatch        = '$args[2] | Out-Null'
                ShowMatch      = $false
                Remove         = $false
                ListProviders  = $true
                ProcessId      = 12
            } | ConvertTo-Json | Set-Content -LiteralPath $sourcePath -Encoding utf8

            & $scriptPath -ConfigPath $sourcePath -ProcessId 34 `
                -ExportConfigPath $effectivePath

            $configuration = Get-Content -LiteralPath $effectivePath -Raw |
                ConvertFrom-Json
            $configuration.Filters | Should -Be @('configured')
            $configuration.TraceProviders | Should -Be @('Microsoft-Windows-DNS-*')
            $configuration.OnMatch | Should -Be '$args[2] | Out-Null'
            $configuration.ShowMatch | Should -BeFalse
            $configuration.ListProviders | Should -BeTrue
            $configuration.ProcessId | Should -Be 34
        }

        It 'Should preserve PID-only trace-all semantics across JSON' {
            $sourcePath = Join-Path $TestDrive 'pid-config.json'
            $effectivePath = Join-Path $TestDrive 'pid-effective-config.json'

            & $scriptPath -ProcessId 42 -ExportConfigPath $sourcePath
            $sourceConfiguration = Get-Content -LiteralPath $sourcePath -Raw |
                ConvertFrom-Json
            $sourceConfiguration.ProcessId | Should -Be 42
            $sourceConfiguration.TraceProviders | Should -BeNullOrEmpty

            & $scriptPath -ConfigPath $sourcePath `
                -ExportConfigPath $effectivePath
            $effectiveConfiguration = Get-Content -LiteralPath $effectivePath -Raw |
                ConvertFrom-Json
            $effectiveConfiguration.ProcessId | Should -Be 42
            $effectiveConfiguration.TraceProviders | Should -BeNullOrEmpty
        }

        It 'Should reject unknown JSON arguments' {
            $configPath = Join-Path $TestDrive 'invalid-config.json'
            @{ UnknownArgument = 'value' } | ConvertTo-Json |
                Set-Content -LiteralPath $configPath -Encoding utf8

            {
                & $scriptPath -ConfigPath $configPath
            } | Should -Throw "*Unknown configuration argument 'UnknownArgument'*"
        }
    }
}
