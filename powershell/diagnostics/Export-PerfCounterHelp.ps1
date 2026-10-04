<#
.SYNOPSIS
    Dumps the help ("Show description") text for every performance counter set and counter.

.DESCRIPTION
    Uses PDH (pdh.dll) - the same API behind PerfMon's Add Counters dialog - so the text matches
    what "Show description" displays. Enumerates counter sets with Get-Counter -ListSet, then calls
    PdhGetCounterInfo(bRetrieveExplainText = TRUE) for every counter path.

    PerfMon greys out "Show description" when the data source is a .BLG log, because a BLG stores
    counter names and values but not explain text. Use -BlgPath to dump the local machine's
    descriptions for just the counters present in a log; counters in the log that are not installed
    locally are reported separately.

.PARAMETER ComputerName
    Machine to read counter definitions from. Default: local. Remote requires the Remote Registry
    service and Performance Log Users (or admin) rights on the target.

.PARAMETER CounterSet
    Wildcard filter on counter set names. Default: *

.PARAMETER BlgPath
    Optional .blg/.csv/.tsv perf log. Limits output to counters present in the log (via relog -q).

.PARAMETER OutputDirectory
    Folder for output files. Default: current directory.

.PARAMETER Format
    Any of Csv, Json, Markdown. Default: all three.

.EXAMPLE
    .\Export-PerfCounterHelp.ps1

.EXAMPLE
    .\Export-PerfCounterHelp.ps1 -CounterSet 'Memory','Processor*' -Format Markdown

.EXAMPLE
    .\Export-PerfCounterHelp.ps1 -BlgPath <path>\perf.blg -OutputDirectory <path>

.NOTES
    File Name  : Export-PerfCounterHelp.ps1
    Author     : jagilber
    Disclaimer : Provided AS-IS without warranty.
    Behavior   : Read-only. Reads counter definitions only; collects no samples and
                 changes nothing on the local or remote machine.
    Requires   : Windows; Windows PowerShell 5.1 or PowerShell 7+.
    Version    : 1.0.0
    Changelog  : 1.0.0 - PDH explain-text dump to CSV/JSON/Markdown with counter type
                 decoding, BLG counter filter, and remote computer support.

.LINK
    https://learn.microsoft.com/windows/win32/api/pdh/nf-pdh-pdhgetcounterinfow
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$ComputerName = $env:COMPUTERNAME,

    [ValidateNotNullOrEmpty()]
    [string[]]$CounterSet = '*',

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$BlgPath,

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = (Get-Location).Path,

    [ValidateSet('Csv', 'Json', 'Markdown')]
    [string[]]$Format = @('Csv', 'Json', 'Markdown')
)

$ErrorActionPreference = 'Stop'

if (-not ('PerfHelp.Pdh' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PerfHelp {
    public class CounterInfo {
        public uint Status;
        public uint Type;
        public int DefaultScale;
        public string FullPath;
        public string Explain;
    }

    public static class Pdh {
        [StructLayout(LayoutKind.Sequential)]
        struct PDH_COUNTER_INFO {
            public uint dwLength, dwType, CVersion, CStatus;
            public int lScale, lDefaultScale;
            public IntPtr dwUserData, dwQueryUserData, szFullPath;
            public IntPtr szMachineName, szObjectName, szInstanceName, szParentInstance;
            public uint dwInstanceIndex;
            public IntPtr szCounterName, szExplainText;
        }

        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhOpenQueryW(string szDataSource, IntPtr dwUserData, out IntPtr phQuery);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhAddCounterW(IntPtr hQuery, string szFullCounterPath, IntPtr dwUserData, out IntPtr phCounter);
        [DllImport("pdh.dll")]
        static extern uint PdhRemoveCounter(IntPtr hCounter);
        [DllImport("pdh.dll")]
        static extern uint PdhCloseQuery(IntPtr hQuery);
        [DllImport("pdh.dll")]
        static extern uint PdhGetCounterInfoW(IntPtr hCounter, bool bRetrieveExplainText, ref uint pdwBufferSize, IntPtr lpBuffer);

        const uint PDH_MORE_DATA = 0x800007D2;

        public static IntPtr OpenQuery() {
            IntPtr q;
            uint rc = PdhOpenQueryW(null, IntPtr.Zero, out q);
            if (rc != 0) throw new InvalidOperationException("PdhOpenQuery failed 0x" + rc.ToString("X8"));
            return q;
        }

        public static void CloseQuery(IntPtr q) { PdhCloseQuery(q); }

        public static CounterInfo GetInfo(IntPtr query, string path) {
            var result = new CounterInfo();
            IntPtr c;
            uint rc = PdhAddCounterW(query, path, IntPtr.Zero, out c);
            if (rc != 0) { result.Status = rc; return result; }
            try {
                uint size = 0;
                rc = PdhGetCounterInfoW(c, true, ref size, IntPtr.Zero);
                if (rc != 0 && rc != PDH_MORE_DATA) { result.Status = rc; return result; }
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try {
                    rc = PdhGetCounterInfoW(c, true, ref size, buf);
                    if (rc != 0) { result.Status = rc; return result; }
                    var info = (PDH_COUNTER_INFO)Marshal.PtrToStructure(buf, typeof(PDH_COUNTER_INFO));
                    result.Type = info.dwType;
                    result.DefaultScale = info.lDefaultScale;
                    result.FullPath = info.szFullPath == IntPtr.Zero ? null : Marshal.PtrToStringUni(info.szFullPath);
                    result.Explain = info.szExplainText == IntPtr.Zero ? null : Marshal.PtrToStringUni(info.szExplainText);
                } finally { Marshal.FreeHGlobal(buf); }
            } finally { PdhRemoveCounter(c); }
            return result;
        }
    }
}
'@
}

# winperf.h counter types -> name + how to read the value
$counterTypes = @{
    0x00000000 = 'PERF_COUNTER_RAWCOUNT_HEX|instantaneous value'
    0x00000100 = 'PERF_COUNTER_LARGE_RAWCOUNT_HEX|instantaneous value'
    0x00000B00 = 'PERF_COUNTER_TEXT|text'
    0x00010000 = 'PERF_COUNTER_RAWCOUNT|instantaneous value'
    0x00010100 = 'PERF_COUNTER_LARGE_RAWCOUNT|instantaneous value'
    0x00400400 = 'PERF_COUNTER_DELTA|change between samples'
    0x00400500 = 'PERF_COUNTER_LARGE_DELTA|change between samples'
    0x00410400 = 'PERF_SAMPLE_COUNTER|rate per second'
    0x00450400 = 'PERF_COUNTER_QUEUELEN_TYPE|average queue length over interval'
    0x00450500 = 'PERF_COUNTER_LARGE_QUEUELEN_TYPE|average queue length over interval'
    0x00550500 = 'PERF_COUNTER_100NS_QUEUELEN_TYPE|average queue length over interval'
    0x00650500 = 'PERF_COUNTER_OBJ_TIME_QUEUELEN_TYPE|average queue length over interval'
    0x10410400 = 'PERF_COUNTER_COUNTER|rate per second'
    0x10410500 = 'PERF_COUNTER_BULK_COUNT|rate per second'
    0x20020400 = 'PERF_RAW_FRACTION|ratio (percent)'
    0x20020500 = 'PERF_LARGE_RAW_FRACTION|ratio (percent)'
    0x20410500 = 'PERF_COUNTER_TIMER|percent of elapsed time'
    0x20470500 = 'PERF_PRECISION_SYSTEM_TIMER|percent of elapsed time'
    0x20510500 = 'PERF_100NSEC_TIMER|percent of elapsed time'
    0x20570500 = 'PERF_PRECISION_100NS_TIMER|percent of elapsed time'
    0x20610500 = 'PERF_OBJ_TIME_TIMER|percent of elapsed time'
    0x20670500 = 'PERF_PRECISION_OBJECT_TIMER|percent of elapsed time'
    0x20C20400 = 'PERF_SAMPLE_FRACTION|ratio (percent)'
    0x21410500 = 'PERF_COUNTER_TIMER_INV|percent of elapsed time (inverse: 100 - busy)'
    0x21510500 = 'PERF_100NSEC_TIMER_INV|percent of elapsed time (inverse: 100 - busy)'
    0x22410500 = 'PERF_COUNTER_MULTI_TIMER|percent of time summed over multiple items'
    0x22510500 = 'PERF_100NSEC_MULTI_TIMER|percent of time summed over multiple items'
    0x23410500 = 'PERF_COUNTER_MULTI_TIMER_INV|percent of time summed over multiple items (inverse)'
    0x23510500 = 'PERF_100NSEC_MULTI_TIMER_INV|percent of time summed over multiple items (inverse)'
    0x30020400 = 'PERF_AVERAGE_TIMER|average time per operation (seconds)'
    0x30240500 = 'PERF_ELAPSED_TIME|elapsed time since start (seconds)'
    0x40000200 = 'PERF_COUNTER_NODATA|no data'
    0x40020500 = 'PERF_AVERAGE_BULK|average count per operation'
    0x40030401 = 'PERF_SAMPLE_BASE|base (denominator)'
    0x40030402 = 'PERF_AVERAGE_BASE|base (denominator)'
    0x40030403 = 'PERF_RAW_BASE|base (denominator)'
    0x40030500 = 'PERF_LARGE_RAW_BASE|base (denominator)'
    0x42030500 = 'PERF_COUNTER_MULTI_BASE|base (denominator)'
}
# key by hex string: PDH returns uint32, hashtable literal keys are int32
$counterTypeMap = @{}
foreach ($k in $counterTypes.Keys) { $counterTypeMap['0x{0:X8}' -f $k] = $counterTypes[$k] }

function Split-CounterPath([string]$Path) {
    # \\machine\Object(instance)\Counter  or  \Object\Counter ; instance may itself contain ( ) or \
    if ($Path -notmatch '^(?:\\\\[^\\]+)?\\(?<obj>[^\\(]+)(?:\((?<inst>.*)\))?\\(?<ctr>[^\\]+)$') { return $null }
    [pscustomobject]@{ Object = $Matches.obj; Instance = $Matches.inst; Counter = $Matches.ctr }
}

$isLocal = $ComputerName -in @('.', 'localhost', $env:COMPUTERNAME)
$prefix = if ($isLocal) { '' } else { "\\$ComputerName" }

# Optional: restrict to counters present in a perf log
$logKeys = $null
if ($BlgPath) {
    $BlgPath = (Resolve-Path $BlgPath).Path
    Write-Verbose "Reading counter list from $BlgPath"
    $logKeys = @{}
    $logObjects = @{}
    foreach ($line in (& relog.exe $BlgPath -q 2>$null)) {
        $p = Split-CounterPath $line.Trim()
        if ($p) {
            $logKeys["$($p.Object)\$($p.Counter)".ToLowerInvariant()] = $line.Trim()
            $logObjects[$p.Object] = $true
        }
    }
    if ($logKeys.Count -eq 0) { throw "relog -q returned no counters for $BlgPath" }
    Write-Verbose "$($logKeys.Count) distinct object\counter pairs in log"
    # enumerating every set is slow (minutes on Windows PowerShell 5.1); list only the log's sets
    if ($CounterSet.Count -eq 1 -and $CounterSet[0] -eq '*') {
        $CounterSet = @($logObjects.Keys | ForEach-Object { [Management.Automation.WildcardPattern]::Escape($_) })
    }
}

$listArgs = @{ ListSet = $CounterSet; ErrorAction = 'SilentlyContinue' }
if (-not $isLocal) { $listArgs.ComputerName = $ComputerName }
$sets = @(Get-Counter @listArgs | Sort-Object CounterSetName)
# a log may hold only counters that are not installed here; report them instead of failing
if ($sets.Count -eq 0 -and -not $logKeys) { throw "No counter sets matched '$($CounterSet -join ',')' on $ComputerName" }

$rows = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[object]]::new()
$matchedLogKeys = @{}
$i = 0
foreach ($set in $sets) {
    $i++
    Write-Progress -Activity "Reading counter help from $ComputerName" -Status $set.CounterSetName -PercentComplete (100 * $i / $sets.Count)
    $query = [PerfHelp.Pdh]::OpenQuery()
    try {
        foreach ($path in ($set.Paths | Select-Object -Unique)) {
            $parts = Split-CounterPath $path
            if (-not $parts) { continue }
            $key = "$($parts.Object)\$($parts.Counter)".ToLowerInvariant()
            if ($logKeys -and -not $logKeys.ContainsKey($key)) { continue }
            if ($logKeys) { $matchedLogKeys[$key] = $true }

            $info = [PerfHelp.Pdh]::GetInfo($query, "$prefix$path")
            if ($info.Status -ne 0) {
                $failures.Add([pscustomobject]@{ Path = $path; Status = ('0x{0:X8}' -f $info.Status) })
                continue
            }
            $typeHex = '0x{0:X8}' -f $info.Type
            $typeName, $kind = if ($counterTypeMap.ContainsKey($typeHex)) { $counterTypeMap[$typeHex] -split '\|' } else { 'UNKNOWN', 'unknown' }
            $rows.Add([pscustomobject][ordered]@{
                ComputerName          = $ComputerName
                CounterSet            = $set.CounterSetName
                CounterSetType        = [string]$set.CounterSetType
                CounterSetDescription = ($set.Description -replace '\s+', ' ').Trim()
                Counter               = $parts.Counter
                Path                  = $path
                CounterType           = $typeName
                CounterTypeHex        = $typeHex
                ValueKind             = $kind
                DefaultScale          = $info.DefaultScale
                Help                  = if ($info.Explain) { ($info.Explain -replace '\s+', ' ').Trim() } else { '' }
            })
        }
    } finally { [PerfHelp.Pdh]::CloseQuery($query) }
}
Write-Progress -Activity "Reading counter help" -Completed

$missingInLocal = @()
if ($logKeys) {
    $missingInLocal = @($logKeys.Keys | Where-Object { -not $matchedLogKeys.ContainsKey($_) } | ForEach-Object { $logKeys[$_] } | Sort-Object)
}

# ---- output ----
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = Join-Path $OutputDirectory ("perfcounter-help-{0}-{1}" -f $ComputerName, $stamp)
$cimArgs = @{ ClassName = 'Win32_OperatingSystem'; ErrorAction = 'SilentlyContinue' }
if (-not $isLocal) { $cimArgs.ComputerName = $ComputerName }
$os = Get-CimInstance @cimArgs
$meta = [ordered]@{
    ComputerName     = $ComputerName
    OsCaption        = $os.Caption
    OsBuild          = $os.Version
    UiCulture        = (Get-UICulture).Name
    GeneratedAt      = (Get-Date).ToString('o')
    Source           = 'PDH PdhGetCounterInfo(bRetrieveExplainText=TRUE) - same text as PerfMon "Show description"'
    BlgPath          = $BlgPath
    CounterSetCount  = @($rows | Select-Object -ExpandProperty CounterSet -Unique).Count
    CounterCount     = $rows.Count
    NoHelpCount      = @($rows | Where-Object { -not $_.Help }).Count
    FailedCount      = $failures.Count
    MissingLocally   = $missingInLocal.Count
}

$written = @()
if ('Csv' -in $Format) {
    $rows | Export-Csv "$base.csv" -NoTypeInformation -Encoding utf8
    $written += "$base.csv"
}
if ('Json' -in $Format) {
    $grouped = foreach ($g in ($rows | Group-Object CounterSet)) {
        [ordered]@{
            CounterSet     = $g.Name
            CounterSetType = $g.Group[0].CounterSetType
            Description    = $g.Group[0].CounterSetDescription
            Counters       = @($g.Group | ForEach-Object {
                    [ordered]@{ Name = $_.Counter; Path = $_.Path; Type = $_.CounterType; ValueKind = $_.ValueKind; Help = $_.Help }
                })
        }
    }
    [ordered]@{ Metadata = $meta; CounterSets = @($grouped); MissingLocally = $missingInLocal; Failures = @($failures) } |
        ConvertTo-Json -Depth 6 | Set-Content "$base.json" -Encoding utf8
    $written += "$base.json"
}
if ('Markdown' -in $Format) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Performance counter help - $ComputerName").AppendLine()
    foreach ($k in $meta.Keys) { if ($meta[$k]) { [void]$sb.AppendLine("- **$k**: $($meta[$k])") } }
    [void]$sb.AppendLine()
    foreach ($g in ($rows | Group-Object CounterSet)) {
        [void]$sb.AppendLine("## $($g.Name) ($($g.Group[0].CounterSetType))").AppendLine()
        if ($g.Group[0].CounterSetDescription) { [void]$sb.AppendLine($g.Group[0].CounterSetDescription).AppendLine() }
        foreach ($r in $g.Group) {
            $help = if ($r.Help) { $r.Help } else { '_(no description)_' }
            [void]$sb.AppendLine("- **$($r.Counter)** - _$($r.ValueKind)_ - $help")
        }
        [void]$sb.AppendLine()
    }
    if ($missingInLocal) {
        [void]$sb.AppendLine("## Counters in log but not installed on $ComputerName").AppendLine()
        $missingInLocal | ForEach-Object { [void]$sb.AppendLine("- ``$_``") }
    }
    Set-Content "$base.md" -Value $sb.ToString() -Encoding utf8
    $written += "$base.md"
}

[pscustomobject]$meta
if ($failures.Count) { Write-Warning "$($failures.Count) counter path(s) could not be read; see Failures in the JSON output." }
if ($missingInLocal) { Write-Warning "$($missingInLocal.Count) counter(s) in the log are not installed on $ComputerName." }
$written | ForEach-Object { Write-Information "Wrote $_" -InformationAction Continue }
