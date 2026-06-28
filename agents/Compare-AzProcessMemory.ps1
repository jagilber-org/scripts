<#
.SYNOPSIS
    Analyze before/after process CSV snapshots for memory footprint differences.

.DESCRIPTION
    Imports process CSV files and computes descriptive statistics (count, sum, mean,
    median, min, max, standard deviation, p95) for key numeric columns. Aggregates
    by ProcessName to handle multiple instances and produces delta reports highlighting
    the largest increases/decreases in PrivateMemoryMB and WorkingSetMB.

    Automatically discovers snapshot directories matching the pattern:
        <RootPath>/processes-*/processes-before/processes-before.csv
        <RootPath>/processes-*/processes-after/processes-after.csv

.PARAMETER RootPath
    Root path containing process snapshot directories. Defaults to current directory.

.PARAMETER BeforePattern
    Glob pattern for before-snapshot CSV files relative to RootPath.
    Default: 'processes-*/processes-before/processes-before.csv'

.PARAMETER AfterPattern
    Glob pattern for after-snapshot CSV files relative to RootPath.
    Default: 'processes-*/processes-after/processes-after.csv'

.PARAMETER OutputFormat
    Output format: 'Markdown' (default) or 'Json'.

.PARAMETER TopN
    Number of top processes to show in each category. Default: 10.

.EXAMPLE
    .\Compare-AzProcessMemory.ps1 -RootPath .\diagnostic-data

.EXAMPLE
    .\Compare-AzProcessMemory.ps1 -OutputFormat Json | ConvertFrom-Json

.NOTES
    Requires PowerShell 7+.
    Expected CSV columns: ProcessName, PrivateMemoryMB, WorkingSetMB, VirtualMemoryMB,
    PagedMemoryMB, Threads, Handles, CPUSeconds
    Version: 1.0.0
#>
[CmdletBinding()]
param(
    [string]$RootPath = (Get-Location).Path,
    [string]$BeforePattern = 'processes-*/processes-before/processes-before.csv',
    [string]$AfterPattern = 'processes-*/processes-after/processes-after.csv',
    [ValidateSet('Markdown', 'Json')]
    [string]$OutputFormat = 'Markdown',
    [int]$TopN = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StatObject {
    param(
        [Parameter(Mandatory)] [double[]]$Values
    )
    if ($null -eq $Values -or $Values.Count -eq 0) {
        return [pscustomobject]@{ Count = 0; Sum = 0; Mean = 0; Median = 0; Min = 0; Max = 0; StdDev = 0; P95 = 0 }
    }
    $sorted = $Values | Sort-Object
    $count = $sorted.Count
    $sum = ($sorted | Measure-Object -Sum).Sum
    $mean = if ($count) { $sum / $count } else { 0 }
    $median = if ($count % 2) { $sorted[([int]($count / 2))] } else { ($sorted[$count / 2 - 1] + $sorted[$count / 2]) / 2 }
    $min = $sorted[0]
    $max = $sorted[-1]
    $sq = 0.0; foreach ($v in $Values) { $sq += [math]::Pow(($v - $mean), 2) }
    $std = if ($count -gt 1) { [math]::Sqrt($sq / ($count - 1)) } else { 0 }
    $p95Index = [math]::Min([int][math]::Ceiling(0.95 * $count) - 1, $count - 1)
    $p95 = $sorted[$p95Index]
    [pscustomobject]@{
        Count  = $count
        Sum    = [math]::Round($sum, 2)
        Mean   = [math]::Round($mean, 2)
        Median = [math]::Round($median, 2)
        Min    = [math]::Round($min, 2)
        Max    = [math]::Round($max, 2)
        StdDev = [math]::Round($std, 2)
        P95    = [math]::Round($p95, 2)
    }
}

function Compare-SnapshotPair {
    param(
        [string]$Label,
        [string]$BeforeFile,
        [string]$AfterFile
    )
    Write-Verbose "Analyzing $Label"
    $before = Import-Csv -Path $BeforeFile | ForEach-Object {
        $_ | Add-Member -NotePropertyName Snapshot 'Before' -Force; $_
    }
    $after = Import-Csv -Path $AfterFile | ForEach-Object {
        $_ | Add-Member -NotePropertyName Snapshot 'After' -Force; $_
    }
    $all = $before + $after

    $numericCols = 'PrivateMemoryMB', 'WorkingSetMB', 'VirtualMemoryMB', 'PagedMemoryMB', 'Threads', 'Handles', 'CPUSeconds'
    foreach ($c in $numericCols) {
        $all | ForEach-Object {
            if ($null -ne $_.$c -and $_.$c -ne '') {
                $parsed = $_.$c -as [double]
                $_.$c = if ($null -ne $parsed) { $parsed } else { 0 }
            }
        }
    }

    $statsBefore = @{}
    $statsAfter = @{}
    foreach ($c in $numericCols) {
        $statsBefore[$c] = Get-StatObject -Values ($before | Where-Object { $null -ne $_.$c } | Select-Object -ExpandProperty $c)
        $statsAfter[$c] = Get-StatObject -Values ($after | Where-Object { $null -ne $_.$c } | Select-Object -ExpandProperty $c)
    }

    $groupBefore = $before | Group-Object -Property ProcessName | ForEach-Object {
        $bm = $_.Group
        [pscustomobject]@{
            ProcessName     = $_.Name
            InstancesBefore = $bm.Count
            PrivateBefore   = ($bm.PrivateMemoryMB | Measure-Object -Sum).Sum
            WorkingBefore   = ($bm.WorkingSetMB | Measure-Object -Sum).Sum
            PeakWSBefore    = ($bm.WorkingSetMB | Measure-Object -Maximum).Maximum
        }
    }
    $groupAfter = $after | Group-Object -Property ProcessName | ForEach-Object {
        $am = $_.Group
        [pscustomobject]@{
            ProcessName    = $_.Name
            InstancesAfter = $am.Count
            PrivateAfter   = ($am.PrivateMemoryMB | Measure-Object -Sum).Sum
            WorkingAfter   = ($am.WorkingSetMB | Measure-Object -Sum).Sum
            PeakWSAfter    = ($am.WorkingSetMB | Measure-Object -Maximum).Maximum
        }
    }

    $join = $groupBefore | ForEach-Object {
        $afterRow = $groupAfter | Where-Object ProcessName -EQ $_.ProcessName
        if (-not $afterRow) {
            $afterRow = [pscustomobject]@{ ProcessName = $_.ProcessName; InstancesAfter = 0; PrivateAfter = 0; WorkingAfter = 0; PeakWSAfter = 0 }
        }
        [pscustomobject]@{
            ProcessName     = $_.ProcessName
            InstancesBefore = $_.InstancesBefore
            InstancesAfter  = $afterRow.InstancesAfter
            PrivateBeforeMB = [math]::Round($_.PrivateBefore, 2)
            PrivateAfterMB  = [math]::Round($afterRow.PrivateAfter, 2)
            PrivateDeltaMB  = [math]::Round(($afterRow.PrivateAfter - $_.PrivateBefore), 2)
            WorkingBeforeMB = [math]::Round($_.WorkingBefore, 2)
            WorkingAfterMB  = [math]::Round($afterRow.WorkingAfter, 2)
            WorkingDeltaMB  = [math]::Round(($afterRow.WorkingAfter - $_.WorkingBefore), 2)
            PeakWSBeforeMB  = [math]::Round($_.PeakWSBefore, 2)
            PeakWSAfterMB   = [math]::Round($afterRow.PeakWSAfter, 2)
            PeakWSDeltaMB   = [math]::Round(($afterRow.PeakWSAfter - $_.PeakWSBefore), 2)
        }
    }

    $onlyAfter = $groupAfter | Where-Object { ($join.ProcessName) -notcontains $_.ProcessName } | ForEach-Object {
        [pscustomobject]@{
            ProcessName     = $_.ProcessName
            InstancesBefore = 0
            InstancesAfter  = $_.InstancesAfter
            PrivateBeforeMB = 0
            PrivateAfterMB  = [math]::Round($_.PrivateAfter, 2)
            PrivateDeltaMB  = [math]::Round($_.PrivateAfter, 2)
            WorkingBeforeMB = 0
            WorkingAfterMB  = [math]::Round($_.WorkingAfter, 2)
            WorkingDeltaMB  = [math]::Round($_.WorkingAfter, 2)
            PeakWSBeforeMB  = 0
            PeakWSAfterMB   = [math]::Round($_.PeakWSAfter, 2)
            PeakWSDeltaMB   = [math]::Round($_.PeakWSAfter, 2)
        }
    }
    $procDeltas = $join + $onlyAfter | Sort-Object -Property PrivateDeltaMB -Descending

    [pscustomobject]@{
        Label            = $Label
        FileBefore       = $BeforeFile
        FileAfter        = $AfterFile
        StatsBefore      = $statsBefore
        StatsAfter       = $statsAfter
        ProcessDeltas    = $procDeltas
        TopPrivateIncr   = $procDeltas | Sort-Object PrivateDeltaMB -Descending | Select-Object -First $TopN
        TopPrivateDecr   = $procDeltas | Sort-Object PrivateDeltaMB | Select-Object -First $TopN
        TopWorkingIncr   = $procDeltas | Sort-Object WorkingDeltaMB -Descending | Select-Object -First $TopN
        TopWorkingDecr   = $procDeltas | Sort-Object WorkingDeltaMB | Select-Object -First $TopN
    }
}

# Discover snapshot pairs dynamically
$beforeFiles = Get-ChildItem -Path $RootPath -Filter 'processes-before.csv' -Recurse -ErrorAction SilentlyContinue
$pairs = @()

foreach ($bf in $beforeFiles) {
    $parentDir = $bf.Directory.Parent
    $label = $parentDir.Name
    $afterFile = Join-Path $parentDir.FullName 'processes-after' 'processes-after.csv'
    if (Test-Path -LiteralPath $afterFile) {
        $pairs += Compare-SnapshotPair -Label $label -BeforeFile $bf.FullName -AfterFile $afterFile
    }
    else {
        Write-Warning "Skipping $label - missing after file: $afterFile"
    }
}

if ($pairs.Count -eq 0) {
    Write-Warning "No valid before/after snapshot pairs found in $RootPath"
    return
}

if ($OutputFormat -eq 'Json') {
    $pairs | ConvertTo-Json -Depth 6
    return
}

Write-Output "# Process Memory Footprint Analysis`n"
foreach ($p in $pairs) {
    Write-Output "## $($p.Label)"
    Write-Output "Files:`nBefore: $($p.FileBefore)`nAfter:  $($p.FileAfter)`n"
    Write-Output '### Summary Statistics (Before vs After)'
    $numericCols = 'PrivateMemoryMB', 'WorkingSetMB', 'PagedMemoryMB', 'Threads', 'Handles'
    foreach ($c in $numericCols) {
        $b = $p.StatsBefore[$c]
        $a = $p.StatsAfter[$c]
        $deltaMean = [math]::Round(($a.Mean - $b.Mean), 2)
        Write-Output "- $c Mean: Before=$($b.Mean) After=$($a.Mean) Delta=$deltaMean (Count: $($b.Count) -> $($a.Count))"
    }
    Write-Output "`n### Top $TopN Private Memory Increases"
    $p.TopPrivateIncr | Select-Object -First $TopN | ForEach-Object {
        Write-Output ("- {0}: Delta={1}MB (Before {2} -> After {3}) Instances {4}->{5}" -f $_.ProcessName, $_.PrivateDeltaMB, $_.PrivateBeforeMB, $_.PrivateAfterMB, $_.InstancesBefore, $_.InstancesAfter)
    }
    Write-Output "`n### Top $TopN Private Memory Decreases"
    $p.TopPrivateDecr | Select-Object -First $TopN | ForEach-Object {
        Write-Output ("- {0}: Delta={1}MB (Before {2} -> After {3})" -f $_.ProcessName, $_.PrivateDeltaMB, $_.PrivateBeforeMB, $_.PrivateAfterMB)
    }
    Write-Output "`n### Top $TopN Working Set Increases"
    $p.TopWorkingIncr | Select-Object -First $TopN | ForEach-Object {
        Write-Output ("- {0}: Delta={1}MB (Before {2} -> After {3})" -f $_.ProcessName, $_.WorkingDeltaMB, $_.WorkingBeforeMB, $_.WorkingAfterMB)
    }
    Write-Output "`n---`n"
}

Write-Output 'End of report.'
