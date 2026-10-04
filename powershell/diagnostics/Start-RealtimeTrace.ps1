<#
.SYNOPSIS
    Starts a realtime Windows ETW provider trace with Packet Monitor.

.DESCRIPTION
    Starts pktmon in realtime provider mode, writes the stream to a log file, and
    displays all events in the console by default. Optional regular-expression
    filters limit console output and highlight matching text.
    Provider names support PowerShell wildcards and are resolved against registered
    ETW providers before tracing begins. Provider listing also searches the Windows
    event catalog and reports which catalog exposed each result. JSON configurations
    can import or export every trace argument; explicit command-line values override
    imported values. Trace operations automatically restart in a new elevated
    PowerShell window when required.

.EXAMPLE
    .\Start-RealtimeTrace.ps1

    Traces the default Windows networking and security providers, displaying every
    event in the console and writing every event to the trace log.

.EXAMPLE
    .\Start-RealtimeTrace.ps1 -TraceProviders 'Microsoft-Windows-DNS-Client' -Filters 'timeout', 'error'

    Traces DNS client events and highlights timeout or error messages.

.EXAMPLE
    .\Start-RealtimeTrace.ps1 -ListProviders -TraceProviders 'Microsoft-Windows-DNS-*'

    Lists Windows event providers and sources whose names match the wildcard pattern.

.EXAMPLE
    .\Start-RealtimeTrace.ps1 -ProcessId 1234

    Traces all ETW providers registered by process ID 1234.

.EXAMPLE
    .\Start-RealtimeTrace.ps1 -ProcessId 1234 -ExportConfigPath .\trace-config.json

    Exports the effective trace arguments to JSON without starting a trace.

.EXAMPLE
    .\Start-RealtimeTrace.ps1 -ConfigPath .\trace-config.json

    Starts tracing with arguments imported from JSON.

.NOTES
    File Name  : Start-RealtimeTrace.ps1
    Author     : jagilber
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.6.0
    Changelog  : 1.0.0 - Add generic realtime Packet Monitor tracing.
                 1.1.0 - Add wildcard provider resolution for tracing and listing.
                 1.1.1 - Return an empty result for unmatched listing filters.
                 1.2.0 - Include classic event sources in provider listing results.
                 1.2.1 - Account for privilege-sensitive Logman provider visibility.
                 1.3.0 - Trace all providers registered by a specified process ID.
                 1.4.0 - Add JSON configuration import and export.
                 1.5.0 - Add self-elevation, partial matching, and trace plan output.
                 1.5.1 - Clarify active trace and console filtering status.
                 1.5.2 - Retry intermittent process provider enumeration failures.
                 1.6.0 - Make console filtering optional and show all events by default.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TraceFilePath = (Join-Path -Path $PWD -ChildPath 'realtime-trace.log'),

    [AllowEmptyCollection()]
    [string[]]$Filters = @(),

    [ValidateNotNullOrEmpty()]
    [string[]]$TraceProviders = @(
        'Microsoft-Windows-HttpService',
        'Microsoft-Windows-WinHttp',
        'Microsoft-Windows-TCPIP',
        'Microsoft-Windows-DNS-Client',
        'Microsoft-Windows-CAPI2',
        'Microsoft-Windows-Schannel-Events'
    ),

    [scriptblock]$OnMatch,

    [bool]$ShowMatch = $true,

    [switch]$Remove,

    [switch]$ListProviders,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$ProcessId = 0,

    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [ValidateNotNullOrEmpty()]
    [string]$ExportConfigPath
)

$pktmonNotRunningStatus = 'Packet Monitor is not running.'
$traceProvidersSpecified = $PSBoundParameters.ContainsKey('TraceProviders')
$configurationArgumentNames = @(
    'TraceFilePath',
    'Filters',
    'TraceProviders',
    'OnMatch',
    'ShowMatch',
    'Remove',
    'ListProviders',
    'ProcessId'
)

function Test-Administrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-RealtimeTraceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if ([IO.Path]::GetExtension($resolvedPath.Path) -ine '.json') {
        throw "Configuration file must use the .json extension: $($resolvedPath.Path)"
    }

    try {
        $configuration = Get-Content -LiteralPath $resolvedPath.Path -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to read JSON configuration '$($resolvedPath.Path)': $($_.Exception.Message)"
    }

    if ($null -eq $configuration -or $configuration -isnot [pscustomobject]) {
        throw 'JSON configuration must contain a single object.'
    }

    $values = @{}
    foreach ($property in $configuration.PSObject.Properties) {
        if ($property.Name -notin $configurationArgumentNames) {
            throw "Unknown configuration argument '$($property.Name)'."
        }

        $value = $property.Value
        switch ($property.Name) {
            { $PSItem -in @('TraceFilePath') } {
                if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                    throw "Configuration argument '$PSItem' must be a non-empty string."
                }
                $values[$PSItem] = $value
            }
            'Filters' {
                if ($null -eq $value) {
                    $values[$PSItem] = [string[]]@()
                    continue
                }

                $items = @($value)
                if (@($items | Where-Object {
                            $PSItem -isnot [string] -or [string]::IsNullOrWhiteSpace($PSItem)
                        }).Count -gt 0) {
                    throw "Configuration argument '$PSItem' must contain non-empty strings."
                }
                $values[$PSItem] = [string[]]$items
            }
            'TraceProviders' {
                if ($null -eq $value) {
                    continue
                }

                $items = @($value)
                if ($items.Count -eq 0 -or @($items | Where-Object {
                            $PSItem -isnot [string] -or [string]::IsNullOrWhiteSpace($PSItem)
                        }).Count -gt 0) {
                    throw "Configuration argument '$PSItem' must contain non-empty strings."
                }
                $values[$PSItem] = [string[]]$items
            }
            'OnMatch' {
                if ($null -eq $value) {
                    $values[$PSItem] = $null
                }
                elseif ($value -is [string]) {
                    $values[$PSItem] = [scriptblock]::Create($value)
                }
                else {
                    throw "Configuration argument '$PSItem' must be a string or null."
                }
            }
            { $PSItem -in @('ShowMatch', 'Remove', 'ListProviders') } {
                if ($value -isnot [bool]) {
                    throw "Configuration argument '$PSItem' must be a Boolean."
                }
                $values[$PSItem] = $value
            }
            'ProcessId' {
                if ($value -isnot [int] -and $value -isnot [long]) {
                    throw "Configuration argument '$PSItem' must be an integer."
                }
                if ([long]$value -lt 0 -or [long]$value -gt [int]::MaxValue) {
                    throw "Configuration argument '$PSItem' must be between 0 and $([int]::MaxValue)."
                }
                $values[$PSItem] = [int]$value
            }
        }
    }

    return $values
}

function Export-RealtimeTraceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ([IO.Path]::GetExtension($resolvedPath) -ine '.json') {
        throw "Configuration file must use the .json extension: $resolvedPath"
    }

    $parentPath = Split-Path -Path $resolvedPath -Parent
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "Configuration output directory does not exist: $parentPath"
    }

    [ordered]@{
        TraceFilePath  = $TraceFilePath
        Filters        = @($Filters)
        TraceProviders = if ($ProcessId -gt 0 -and -not $traceProvidersSpecified) {
            $null
        }
        else {
            @($TraceProviders)
        }
        OnMatch        = if ($null -eq $OnMatch) { $null } else { $OnMatch.ToString() }
        ShowMatch      = [bool]$ShowMatch
        Remove         = [bool]$Remove
        ListProviders  = [bool]$ListProviders
        ProcessId      = [int]$ProcessId
    } |
        ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $resolvedPath -Encoding utf8
}

function Start-ElevatedRealtimeTrace {
    [CmdletBinding()]
    param()

    $temporaryConfigPath = Join-Path ([IO.Path]::GetTempPath()) (
        'Start-RealtimeTrace-{0}.json' -f [guid]::NewGuid()
    )
    Export-RealtimeTraceConfiguration -Path $temporaryConfigPath

    $powerShellPath = (Get-Process -Id $PID).Path
    $escapedWorkingDirectory = $PWD.Path.Replace("'", "''")
    $escapedScriptPath = $script:PSCommandPath.Replace("'", "''")
    $escapedConfigPath = $temporaryConfigPath.Replace("'", "''")
    $elevatedCommand = @"
try {
    Set-Location -LiteralPath '$escapedWorkingDirectory'
    & '$escapedScriptPath' -ConfigPath '$escapedConfigPath'
}
finally {
    Remove-Item -LiteralPath '$escapedConfigPath' -Force -ErrorAction SilentlyContinue
}
"@
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($elevatedCommand)
    )

    Write-Host 'Restarting realtime tracing in a new elevated PowerShell window.' `
        -ForegroundColor Yellow
    try {
        Start-Process -FilePath $powerShellPath -Verb RunAs -WorkingDirectory $PWD.Path `
            -ArgumentList @('-NoExit', '-NoProfile', '-EncodedCommand', $encodedCommand)
    }
    catch {
        Remove-Item -LiteralPath $temporaryConfigPath -Force -ErrorAction SilentlyContinue
        throw "Failed to start elevated PowerShell: $($_.Exception.Message)"
    }
}

function Get-RealtimeTraceProvider {
    [CmdletBinding()]
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Id,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$NamePattern,

        [switch]$AllowNoMatch,

        [switch]$AllowPartialMatch,

        [switch]$IncludeEventSources
    )

    $maximumAttempts = if ($Id -gt 0) { 5 } else { 1 }
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        $providerOutput = if ($Id -gt 0) {
            Write-Verbose "Querying providers for process ID $Id (attempt $attempt)."
            logman query providers -pid $Id
        }
        else {
            Write-Verbose 'Querying registered ETW providers.'
            logman query providers
        }

        $queryExitCode = $LASTEXITCODE
        if ($queryExitCode -eq 0) {
            break
        }

        Write-Verbose "Logman provider query failed with exit code $queryExitCode."
    }

    if ($queryExitCode -ne 0) {
        throw "logman failed to query ETW providers with exit code $queryExitCode."
    }

    $availableProviders = @(
        $providerOutput | ForEach-Object {
            if ($PSItem -match '^\s*(?<Provider>.*?)\s+(?<Guid>\{[0-9A-Fa-f-]{36}\})\s*$') {
                [pscustomobject]@{
                    Provider        = $Matches.Provider.Trim()
                    Guid            = $Matches.Guid
                    TraceCapable    = $true
                    DiscoverySource = 'Logman'
                }
            }
        }
    )

    if ($IncludeEventSources -and $Id -eq 0) {
        $knownProviderNames = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($provider in $availableProviders) {
            $null = $knownProviderNames.Add($provider.Provider)
        }

        foreach ($pattern in $NamePattern) {
            $eventSources = @(
                Get-WinEvent -ListProvider $pattern -ErrorAction SilentlyContinue
            )
            foreach ($eventSource in $eventSources) {
                if (-not $knownProviderNames.Add($eventSource.Name)) {
                    continue
                }

                $availableProviders += [pscustomobject]@{
                    Provider        = $eventSource.Name
                    Guid            = "{$($eventSource.Id.ToString().ToUpperInvariant())}"
                    TraceCapable    = $null
                    DiscoverySource = 'EventLog'
                }
            }
        }
    }

    $matchedProviderNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($pattern in $NamePattern) {
        $wildcard = [WildcardPattern]::new(
            $pattern,
            [Management.Automation.WildcardOptions]::IgnoreCase
        )
        $patternMatches = @($availableProviders | Where-Object { $wildcard.IsMatch($PSItem.Provider) })
        if ($patternMatches.Count -eq 0) {
            $scope = if ($Id -gt 0) { "process ID $Id" } else { 'registered providers' }
            if ($AllowNoMatch) {
                continue
            }

            if ($AllowPartialMatch) {
                Write-Warning "Provider pattern '$pattern' matched no $scope."
                continue
            }

            throw "Provider pattern '$pattern' matched no $scope."
        }

        foreach ($provider in $patternMatches) {
            $null = $matchedProviderNames.Add($provider.Provider)
        }
    }

    if ($matchedProviderNames.Count -eq 0 -and -not $AllowNoMatch) {
        $scope = if ($Id -gt 0) { "process ID $Id" } else { 'registered providers' }
        throw "None of the provider patterns matched $scope."
    }

    $availableProviders |
        Where-Object { $matchedProviderNames.Contains($PSItem.Provider) } |
        Sort-Object -Property Provider
}

function Show-RealtimeTraceProvider {
    [CmdletBinding()]
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Id,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$NamePattern
    )

    if ($Id -gt 0) {
        Write-Verbose "Listing matching providers for process ID $Id."
    }
    else {
        Write-Verbose 'Listing matching registered ETW providers.'
    }

    $includeEventSources = $Id -eq 0
    Get-RealtimeTraceProvider -Id $Id -NamePattern $NamePattern -AllowNoMatch `
        -IncludeEventSources:$includeEventSources
}

function Stop-PktMonRealtimeTrace {
    [CmdletBinding()]
    param()

    $status = pktmon status 2>&1 | Out-String
    if ($status -imatch [regex]::Escape($pktmonNotRunningStatus)) {
        Write-Verbose 'Packet Monitor is not running.'
        return
    }

    Write-Verbose 'Stopping Packet Monitor.'
    pktmon stop | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "pktmon stop failed with exit code $LASTEXITCODE."
    }
}

function Start-PktMonRealtimeTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Provider
    )

    return Start-Job -ScriptBlock {
        param([string[]]$ProviderName)

        $arguments = [Collections.Generic.List[string]]::new()
        foreach ($argument in @('start', '-t', '-m', 'real-time')) {
            $arguments.Add($argument)
        }
        foreach ($name in $ProviderName) {
            $arguments.Add('-p')
            $arguments.Add($name)
        }

        & pktmon @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "pktmon start failed with exit code $LASTEXITCODE."
        }
    } -ArgumentList (,$Provider)
}

function Write-RealtimeTracePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Provider,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Id
    )

    $scope = if ($Id -gt 0) { " for process ID $Id" } else { '' }
    Write-Host "Resolved $($Provider.Count) trace provider(s)$scope`:" `
        -ForegroundColor Cyan
    foreach ($item in $Provider) {
        Write-Host "  $($item.Provider)  $($item.Guid)"
    }
    Write-Host "Trace output: $FilePath" -ForegroundColor Cyan
}

function Write-HighlightedMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [text.RegularExpressions.Match]$Match,

        [Parameter(Mandatory)]
        [string]$InputString
    )

    $green = "$([char]27)[32m"
    $reset = "$([char]27)[0m"
    $prefix = $InputString.Substring(0, $Match.Index)
    $suffix = $InputString.Substring($Match.Index + $Match.Length)
    Write-Host ($prefix + $green + $Match.Value + $reset + $suffix)
}

function Watch-PktMonRealtimeTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Job]$Job,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [AllowNull()]
        [regex]$Filter,

        [scriptblock]$MatchAction
    )

    $matchCount = 0
    Write-Host 'Trace is running. Press Ctrl+C to stop and clean up Packet Monitor.' `
        -ForegroundColor Green
    Write-Host "All events are written to: $FilePath" -ForegroundColor Cyan
    if ($null -eq $Filter) {
        Write-Host 'Console output: all events (no filters configured).' `
            -ForegroundColor Cyan
    }
    else {
        Write-Host "Console output is limited to matches for: $Filter" `
            -ForegroundColor Cyan
    }
    Receive-Job -Job $Job -Wait -AutoRemoveJob |
        Tee-Object -FilePath $FilePath |
        ForEach-Object {
            $line = [string]$PSItem
            $match = if ($null -eq $Filter) {
                [regex]::Match($line, '.*')
            }
            else {
                $Filter.Match($line)
            }

            if (-not $match.Success) { return }
            $matchCount++
            if ($ShowMatch) {
                if ($null -eq $Filter) {
                    Write-Host $line
                }
                else {
                    Write-HighlightedMatch -Match $match -InputString $line
                }
            }
            if ($null -ne $MatchAction) {
                & $MatchAction $match $line $matchCount
            }
        }
}

function Invoke-RealtimeTrace {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($ExportConfigPath) {
        if ($PSCmdlet.ShouldProcess($ExportConfigPath, 'Export realtime trace configuration')) {
            Export-RealtimeTraceConfiguration -Path $ExportConfigPath
        }
        return
    }

    if ($ListProviders) {
        $providerPatterns = if ($traceProvidersSpecified) { $TraceProviders } else { @('*') }
        Show-RealtimeTraceProvider -Id $ProcessId -NamePattern $providerPatterns
        return
    }

    if (-not (Test-Administrator)) {
        if ($PSCmdlet.ShouldProcess(
                'Elevated PowerShell session',
                'Restart realtime tracing as administrator'
            )) {
            Start-ElevatedRealtimeTrace
        }
        return
    }

    if ($null -eq (Get-Command -Name pktmon -ErrorAction SilentlyContinue)) {
        throw 'pktmon was not found. Packet Monitor is included in supported versions of Windows 10 and Windows Server 2019 or later.'
    }

    if ($Remove) {
        if ($PSCmdlet.ShouldProcess('Packet Monitor', 'Stop realtime trace')) {
            Stop-PktMonRealtimeTrace
        }
        return
    }

    $regex = $null
    if ($Filters.Count -gt 0) {
        $regexFilter = $Filters -join '|'
        try {
            $regex = [regex]::new(
                $regexFilter,
                [text.regularexpressions.regexoptions]::Compiled -bor
                    [text.regularexpressions.regexoptions]::IgnoreCase
            )
        }
        catch {
            throw "Filters do not form a valid regular expression: $($_.Exception.Message)"
        }
    }

    $resolvedTracePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TraceFilePath)
    $traceDirectory = Split-Path -Path $resolvedTracePath -Parent
    if (-not (Test-Path -LiteralPath $traceDirectory -PathType Container)) {
        throw "Trace output directory does not exist: $traceDirectory"
    }

    $providerPatterns = if ($ProcessId -gt 0 -and -not $traceProvidersSpecified) {
        @('*')
    }
    else {
        $TraceProviders
    }
    $resolvedProviderRecords = @(
        Get-RealtimeTraceProvider -Id $ProcessId -NamePattern $providerPatterns `
            -AllowPartialMatch
    )
    $resolvedProviders = @($resolvedProviderRecords.Provider)
    Write-RealtimeTracePlan -Provider $resolvedProviderRecords `
        -FilePath $resolvedTracePath -Id $ProcessId

    $traceJob = $null
    try {
        if ($PSCmdlet.ShouldProcess('Packet Monitor', 'Stop any existing trace')) {
            Stop-PktMonRealtimeTrace
        }
        $traceScope = if ($ProcessId -gt 0) {
            "$($resolvedProviders.Count) providers for process ID $ProcessId"
        }
        else {
            "$($resolvedProviders.Count) providers"
        }
        if (-not $PSCmdlet.ShouldProcess($resolvedTracePath, "Start realtime trace for $traceScope")) {
            return
        }

        Write-Host 'Starting Packet Monitor realtime trace.' -ForegroundColor Green
        $traceJob = Start-PktMonRealtimeTrace -Provider $resolvedProviders
        Watch-PktMonRealtimeTrace -Job $traceJob -FilePath $resolvedTracePath -Filter $regex -MatchAction $OnMatch
    }
    finally {
        if ($null -ne $traceJob) {
            Stop-PktMonRealtimeTrace
            if ($traceJob.State -in @('NotStarted', 'Running')) {
                Stop-Job -Job $traceJob -ErrorAction SilentlyContinue
            }
            Remove-Job -Job $traceJob -Force -ErrorAction SilentlyContinue
        }
    }
}

$importedConfiguration = @{}
if ($ConfigPath) {
    $importedConfiguration = Import-RealtimeTraceConfiguration -Path $ConfigPath
    foreach ($argumentName in $configurationArgumentNames) {
        if (-not $PSBoundParameters.ContainsKey($argumentName) -and
            $importedConfiguration.ContainsKey($argumentName)) {
            Set-Variable -Name $argumentName -Value $importedConfiguration[$argumentName] -Scope Script
        }
    }
    if ($importedConfiguration.ContainsKey('TraceProviders')) {
        $traceProvidersSpecified = $true
    }
}

Invoke-RealtimeTrace
