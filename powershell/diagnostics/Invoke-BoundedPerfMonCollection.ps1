<#
.SYNOPSIS
    Collects a bounded local PerfMon log.

.DESCRIPTION
    Creates a local Performance Logs and Alerts Data Collector Set by using
    Logman. The collector writes a circular BLG and is independently bounded by
    elapsed time, sample count, and file size.

    The fixed counter set covers CPU mode and queueing, memory commitment and
    faults, pagefile usage, disk latency/queue/IOPS/throughput, volume free
    space, network throughput/capacity/errors/discards/TCP retransmits, and
    per-process CPU, memory, faults, and I/O. It does not collect thread stacks,
    wait chains, packets, or application-readiness markers.

    Run this script locally from 64-bit Windows PowerShell 5.1 as an
    administrator. It does not collect from remote computers, open firewall
    ports, request credentials, or create a ZIP package.

.PARAMETER Action
    Selects Start, Status, Stop, or Cleanup. Start, Stop, and Cleanup require
    elevation. Cleanup removes the Data Collector Set but preserves its output.

.PARAMETER OutputRoot
    Local fixed-drive directory for collector state and output. Paths containing
    whitespace are rejected because Logman receives paths as command arguments.

.PARAMETER DurationMinutes
    Maximum runtime in minutes. The accepted range is 1 through 60.

.PARAMETER SampleIntervalSeconds
    Sampling interval in seconds. The accepted range is 2 through 60.

.PARAMETER MaximumLogMB
    Maximum circular BLG size in megabytes. The accepted range is 100 through
    1024.

.PARAMETER MinimumFreeMB
    Required free space on the output drive before collection starts. The
    accepted range is 2048 through 20480 MB.

.EXAMPLE
    .\Invoke-BoundedPerfMonCollection.ps1 -Action Start

    Starts the local collector with the default 30-minute, five-second, and
    500-MB bounds.

.EXAMPLE
    .\Invoke-BoundedPerfMonCollection.ps1 -Action Status

    Reports the collector state, current BLG size, and output directory.

.EXAMPLE
    .\Invoke-BoundedPerfMonCollection.ps1 -Action Stop

    Stops and removes the collector, then verifies that the BLG is readable and
    contains samples.

.EXAMPLE
    .\Invoke-BoundedPerfMonCollection.ps1 -Action Cleanup

    Removes a remaining collector while preserving all collected files.

.NOTES
    File Name  : Invoke-BoundedPerfMonCollection.ps1
    Author     : jagilber
    Disclaimer : Provided AS-IS without warranty. Test collection settings on a
                 representative non-production system before broader use.
    Runtime    : 64-bit Windows PowerShell 5.1 (Desktop edition).
    Dependencies: Built-in Logman, Import-Counter, and Performance Logs and
                  Alerts components.
    Data       : BLG output contains the computer name, process-instance names,
                 and system performance metadata. Review it before sharing.
    Version    : 2.1.0
    Changelog  : 1.0.0 - Add bounded local and multi-machine collection.
                 2.0.0 - Remove remote collection, dynamic counters, PowerShell
                 7 compatibility, coverage reports, and ZIP packaging.
                 2.1.0 - Add fixed memory-fault, disk-IOPS, volume-capacity,
                 network-health, TCP-retransmit, and process-attribution counters.

.LINK
    https://learn.microsoft.com/windows-server/administration/windows-commands/logman-create-counter
#>

#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    '',
    Justification = 'Top-level parameters are consumed by private functions in the same script scope.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Justification = 'Private lifecycle functions are reachable only through explicit actions.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Start', 'Status', 'Stop', 'Cleanup')]
    [string]$Action,

    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (-not [IO.Path]::IsPathRooted($_)) { throw 'OutputRoot must be an absolute path.' }
        if ($_ -match '\s') { throw 'OutputRoot cannot contain spaces.' }
        $true
    })]
    [string]$OutputRoot = 'C:\PerfLogs',

    [ValidateRange(1, 60)]
    [int]$DurationMinutes = 30,

    [ValidateRange(2, 60)]
    [int]$SampleIntervalSeconds = 5,

    [ValidateRange(100, 1024)]
    [int]$MaximumLogMB = 500,

    [ValidateRange(2048, 20480)]
    [int]$MinimumFreeMB = 2048
)

$ErrorActionPreference = 'Stop'
$script:StatePath = Join-Path $OutputRoot 'Bounded-PerfMon-Current.json'
$script:StatusNames = @{
    '-1' = 'NotFound'
    '0' = 'Stopped'
    '1' = 'Running'
    '2' = 'Compiling'
    '3' = 'Pending'
    '4' = 'Undefined'
}

function Assert-Runtime {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5 -or
        $PSVersionTable.PSVersion.Minor -lt 1) {
        throw 'This collector requires Windows PowerShell 5.1. Run powershell.exe, not pwsh.exe.'
    }
    if (-not [Environment]::Is64BitProcess) {
        throw 'This collector requires 64-bit Windows PowerShell. Open System32\WindowsPowerShell\v1.0\powershell.exe.'
    }
    if (-not (Get-Command logman.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Required Windows tool logman.exe was not found.'
    }
    if (-not (Get-Command Import-Counter -CommandType Cmdlet -ErrorAction SilentlyContinue)) {
        throw 'Required Windows PowerShell cmdlet Import-Counter was not found.'
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'Open 64-bit Windows PowerShell 5.1 as Administrator and run the command again.'
    }
}

function Invoke-Logman {
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    $output = & logman.exe @ArgumentList 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Logman failed with exit code $LASTEXITCODE. $($output.Trim())"
    }
}

function Get-CollectorStatus {
    param([Parameter(Mandatory)][string]$CollectorName)

    try {
        $collector = New-Object -ComObject Pla.DataCollectorSet
        $collector.Query($CollectorName, $null)
        return [int]$collector.Status
    }
    catch [Runtime.InteropServices.COMException] {
        if ($_.Exception.HResult -eq -2144337918) { return -1 }
        throw
    }
}

function Get-StatusName {
    param([Parameter(Mandatory)][int]$Status)

    $key = [string]$Status
    if ($script:StatusNames.ContainsKey($key)) { return $script:StatusNames[$key] }
    return "Unknown($Status)"
}

function Get-BaseCounter {
    return @(
        '\Processor Information(*)\% Processor Time'
        '\Processor Information(_Total)\% User Time'
        '\Processor Information(_Total)\% Privileged Time'
        '\Processor Information(_Total)\% DPC Time'
        '\Processor Information(_Total)\% Interrupt Time'
        '\System\Processor Queue Length'
        '\System\Context Switches/sec'
        '\Memory\Available MBytes'
        '\Memory\% Committed Bytes In Use'
        '\Memory\Page Faults/sec'
        '\Memory\Pages/sec'
        '\Memory\Page Reads/sec'
        '\Memory\Page Writes/sec'
        '\Memory\Pool Paged Bytes'
        '\Memory\Pool Nonpaged Bytes'
        '\Paging File(_Total)\% Usage'
        '\PhysicalDisk(*)\% Idle Time'
        '\PhysicalDisk(*)\Avg. Disk sec/Read'
        '\PhysicalDisk(*)\Avg. Disk sec/Write'
        '\PhysicalDisk(*)\Avg. Disk Queue Length'
        '\PhysicalDisk(*)\Current Disk Queue Length'
        '\PhysicalDisk(*)\Disk Bytes/sec'
        '\PhysicalDisk(*)\Disk Reads/sec'
        '\PhysicalDisk(*)\Disk Writes/sec'
        '\PhysicalDisk(*)\Disk Read Bytes/sec'
        '\PhysicalDisk(*)\Disk Write Bytes/sec'
        '\LogicalDisk(*)\% Free Space'
        '\LogicalDisk(*)\Free Megabytes'
        '\Network Interface(*)\Bytes Total/sec'
        '\Network Interface(*)\Bytes Sent/sec'
        '\Network Interface(*)\Bytes Received/sec'
        '\Network Interface(*)\Current Bandwidth'
        '\Network Interface(*)\Packets Received Errors'
        '\Network Interface(*)\Packets Outbound Errors'
        '\Network Interface(*)\Packets Received Discarded'
        '\Network Interface(*)\Packets Outbound Discarded'
        '\TCPv4\Segments Retransmitted/sec'
        '\Process(*)\ID Process'
        '\Process(*)\Creating Process ID'
        '\Process(*)\Elapsed Time'
        '\Process(*)\% Processor Time'
        '\Process(*)\% Privileged Time'
        '\Process(*)\Working Set - Private'
        '\Process(*)\Private Bytes'
        '\Process(*)\Page Faults/sec'
        '\Process(*)\IO Read Bytes/sec'
        '\Process(*)\IO Write Bytes/sec'
        '\Process(*)\IO Other Bytes/sec'
        '\Process(*)\Thread Count'
        '\Process(*)\Handle Count'
    )
}

function Read-State {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) {
        throw "No collection state was found at $script:StatePath."
    }
    try {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Collection state is not valid JSON: $script:StatePath"
    }

    if ($state.SchemaVersion -notin @(1, 2) -or
        [string]::IsNullOrWhiteSpace($state.CollectorName) -or
        [string]::IsNullOrWhiteSpace($state.OutputRoot) -or
        [string]::IsNullOrWhiteSpace($state.OutputDirectory)) {
        throw "Collection state is incomplete or unsupported: $script:StatePath"
    }
    return $state
}

function Write-State {
    param([Parameter(Mandatory)]$State)

    $json = $State | ConvertTo-Json -Depth 3
    $json | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    $json | Set-Content -LiteralPath (Join-Path $State.OutputDirectory 'Collector-State.json') -Encoding UTF8
}

function Stop-Collector {
    param([Parameter(Mandatory)][string]$CollectorName)

    $status = Get-CollectorStatus $CollectorName
    if ($status -eq -1 -or $status -eq 0) { return }
    if ($status -eq 4) { throw "Collector status is Undefined: $CollectorName" }

    $collector = New-Object -ComObject Pla.DataCollectorSet
    $collector.Query($CollectorName, $null)
    $collector.Stop($true) | Out-Null
    if ((Get-CollectorStatus $CollectorName) -ne 0) {
        throw "Collector did not reach Stopped state: $CollectorName"
    }
}

function Remove-Collector {
    param([Parameter(Mandatory)][string]$CollectorName)

    if ((Get-CollectorStatus $CollectorName) -eq -1) { return }
    Stop-Collector $CollectorName
    Invoke-Logman @('delete', $CollectorName)
    if ((Get-CollectorStatus $CollectorName) -ne -1) {
        throw "Collector still exists after deletion: $CollectorName"
    }
}

function Get-OutputDrive {
    $fullOutputRoot = [IO.Path]::GetFullPath($OutputRoot)
    $driveRoot = [IO.Path]::GetPathRoot($fullOutputRoot)
    $drive = New-Object -TypeName IO.DriveInfo -ArgumentList $driveRoot
    if (-not $drive.IsReady -or $drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw "OutputRoot must be on a ready local fixed drive: $OutputRoot"
    }
    return $drive
}

function Start-Collection {
    Assert-Administrator
    if (Test-Path -LiteralPath $script:StatePath) {
        throw "A previous collection state exists. Run Status, Stop, or Cleanup first: $script:StatePath"
    }

    $drive = Get-OutputDrive
    $freeMB = [math]::Floor($drive.AvailableFreeSpace / 1MB)
    if ($freeMB -lt $MinimumFreeMB) {
        throw "$($drive.Name) has $freeMB MB free; $MinimumFreeMB MB is required."
    }

    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $collectorName = "Bounded-PerfMon-$runId"
    $outputDirectory = Join-Path $OutputRoot $collectorName
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null

    $maximumSamples = [math]::Floor(($DurationMinutes * 60) / $SampleIntervalSeconds)
    $state = [pscustomobject]@{
        SchemaVersion = 2
        CollectorName = $collectorName
        OutputRoot = $OutputRoot
        OutputDirectory = $outputDirectory
        CounterFile = Join-Path $outputDirectory 'Counters.txt'
        OutputBase = Join-Path $outputDirectory 'PerfMon'
        StartedUtc = $null
        DurationMinutes = $DurationMinutes
        SampleIntervalSeconds = $SampleIntervalSeconds
        MaximumSamples = $maximumSamples
        MaximumLogMB = $MaximumLogMB
    }

    $duration = [TimeSpan]::FromMinutes($DurationMinutes).ToString('hh\:mm\:ss')
    $interval = [TimeSpan]::FromSeconds($SampleIntervalSeconds).ToString('hh\:mm\:ss')
    try {
        $counters = @(Get-BaseCounter)
        $counters | Set-Content -LiteralPath $state.CounterFile -Encoding ASCII
        $writtenCounters = @(Get-Content -LiteralPath $state.CounterFile)
        if ($writtenCounters.Count -ne $counters.Count) {
            throw "Counter file validation failed: $($state.CounterFile)"
        }
        Write-State $state

        Invoke-Logman @(
            'create', 'counter', $collectorName,
            '-o', $state.OutputBase,
            '-f', 'bincirc', '-max', [string]$MaximumLogMB,
            '-si', $interval, '-rf', $duration,
            '-sc', [string]$maximumSamples,
            '-cf', $state.CounterFile, '-y'
        )
        Invoke-Logman @('start', $collectorName)

        $status = Get-CollectorStatus $collectorName
        if ($status -notin @(1, 3)) {
            throw "Collector did not start. Status: $(Get-StatusName $status)"
        }
        $state.StartedUtc = [DateTime]::UtcNow.ToString('o')
        Write-State $state
        Show-Status
    }
    catch {
        $startError = $_.Exception.Message
        try { Remove-Collector $collectorName } catch { Write-Warning $_.Exception.Message }
        try {
            if ((Get-CollectorStatus $collectorName) -eq -1 -and
                (Test-Path -LiteralPath $script:StatePath)) {
                Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Unable to remove recovery state: $($_.Exception.Message)"
        }
        throw $startError
    }
}

function Show-Status {
    $state = Read-State
    $status = Get-CollectorStatus $state.CollectorName
    $blg = Get-ChildItem -LiteralPath $state.OutputDirectory -Filter '*.blg' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    [pscustomobject]@{
        Status = Get-StatusName $status
        CurrentBlgMB = if ($blg) { [math]::Round($blg.Length / 1MB, 2) } else { 0 }
        BlgPath = if ($blg) { $blg.FullName } else { $null }
        OutputDirectory = $state.OutputDirectory
    }
}

function Complete-Collection {
    param([switch]$CleanupOnly)

    Assert-Administrator
    $state = Read-State
    $errors = New-Object Collections.Generic.List[string]
    $collectorAbsent = $false
    $blg = $null
    $sampleCount = $null

    try {
        Stop-Collector $state.CollectorName
        if (-not $CleanupOnly) {
            $blg = Get-ChildItem -LiteralPath $state.OutputDirectory -Filter '*.blg' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if (-not $blg -or $blg.Length -le 0) {
                $errors.Add('No non-empty BLG was created.')
            }
            else {
                try {
                    $escapedBlgPath = [WildcardPattern]::Escape($blg.FullName)
                    $summary = Import-Counter -Path $escapedBlgPath -Summary -ErrorAction Stop
                    $sampleCount = [long]$summary.SampleCount
                    if ($sampleCount -le 0) { $errors.Add('BLG contains no samples.') }
                }
                catch {
                    $errors.Add("BLG validation failed: $($_.Exception.Message)")
                }
            }
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
    }
    finally {
        try {
            Remove-Collector $state.CollectorName
            $collectorAbsent = ((Get-CollectorStatus $state.CollectorName) -eq -1)
        }
        catch {
            $errors.Add($_.Exception.Message)
        }

        if ($collectorAbsent -and ($CleanupOnly -or $errors.Count -eq 0)) {
            try {
                Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction Stop
            }
            catch {
                $errors.Add("Unable to remove recovery state: $($_.Exception.Message)")
            }
        }
        elseif ($collectorAbsent) {
            $errors.Add("Recovery state was retained at $script:StatePath. Run Cleanup after copying the output.")
        }
        else {
            $errors.Add("Collector recovery state was retained at $script:StatePath.")
        }
    }

    if ($errors.Count -gt 0) {
        throw "Collection output was preserved at $($state.OutputDirectory). $($errors -join ' ')"
    }

    [pscustomobject]@{
        Validation = if ($CleanupOnly) { 'NOT RUN' } else { 'PASS' }
        CollectorPresent = (-not $collectorAbsent)
        BlgPath = if ($blg) { $blg.FullName } else { $null }
        BlgMB = if ($blg) { [math]::Round($blg.Length / 1MB, 2) } else { $null }
        SampleCount = $sampleCount
        OutputDirectory = $state.OutputDirectory
    }
}

Assert-Runtime

switch ($Action) {
    'Start' { Start-Collection }
    'Status' { Show-Status }
    'Stop' { Complete-Collection }
    'Cleanup' { Complete-Collection -CleanupOnly }
}
