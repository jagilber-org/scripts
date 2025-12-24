# Diagnostics & Monitoring Scripts

This directory contains 9 PowerShell scripts for system diagnostics, performance monitoring, and troubleshooting.

## Scripts

### Event Log Management
- **Manage-EventLog.ps1** - Create, configure, and manage Windows Event Logs
- **Get-EventLogMetadata.ps1** - Retrieve event log schema and metadata

### Performance Monitoring
- **Show-PerfMonGraph.ps1** - Display real-time performance counter graphs in console
- **Invoke-PerfMonAction.ps1** - Execute actions based on performance thresholds

### Process Monitoring
- **Watch-Process.ps1** - Monitor process lifecycle and resource usage
- **Get-ProcessMemory.ps1** - Detailed process memory analysis and summary
- **Start-ProcessMonitor.ps1** - Launch Process Monitor with event task integration

### Tracing & ETL
- **Convert-EtlFile.ps1** - Parse and convert ETL trace files to readable formats
- **Start-DotNetTrace.ps1** - Collect .NET application traces for diagnostics

### Windows Diagnostics
- **Get-WindowsLogonDiagnostics.ps1** - Diagnose Windows logon issues and failures

## Common Use Cases

### Monitor Process Memory
```powershell
.\Get-ProcessMemory.ps1 -ProcessName "w3wp" | Format-Table
```

### Real-Time Performance Graph
```powershell
.\Show-PerfMonGraph.ps1 -Counter "\Processor(_Total)\% Processor Time" -Interval 1
```

### Collect .NET Trace
```powershell
.\Start-DotNetTrace.ps1 -ProcessId 1234 -Duration 60 -Output "C:\traces\app.nettrace"
```

### Parse ETL Files
```powershell
.\Convert-EtlFile.ps1 -EtlFile "C:\logs\trace.etl" -OutputFormat CSV -OutputPath "C:\logs\parsed.csv"
```

### Diagnose Logon Issues
```powershell
.\Get-WindowsLogonDiagnostics.ps1 -Username "DOMAIN\user" -StartTime (Get-Date).AddHours(-24)
```

## Prerequisites

### Required Tools
- **Windows Performance Monitor**: Built into Windows
- **.NET Trace Tool**: `dotnet tool install --global dotnet-trace`
- **Process Monitor**: [Sysinternals Suite](https://learn.microsoft.com/en-us/sysinternals/)
- **Administrator Rights**: Most scripts require elevation

### PowerShell Modules
```powershell
# For event log management
Import-Module Microsoft.PowerShell.Diagnostics
```

## Performance Counter Examples

Common counters to monitor:

### CPU
- `\Processor(_Total)\% Processor Time`
- `\System\Processor Queue Length`

### Memory
- `\Memory\Available MBytes`
- `\Memory\Pages/sec`
- `\Process(*)\Working Set`

### Disk
- `\PhysicalDisk(*)\% Disk Time`
- `\PhysicalDisk(*)\Avg. Disk Queue Length`

### Network
- `\Network Interface(*)\Bytes Total/sec`
- `\TCPv4\Connections Established`

## ETL Trace Collection

### Enable ETL Tracing
```powershell
# Network trace
netsh trace start capture=yes tracefile=C:\traces\network.etl

# Stop trace
netsh trace stop

# Convert to readable format
.\Convert-EtlFile.ps1 -EtlFile "C:\traces\network.etl"
```

## Process Monitor Integration

Start Process Monitor with event task:
```powershell
.\Start-ProcessMonitor.ps1 -Filter "Process Name is w3wp.exe" -EventId 4688
```

## Troubleshooting Scenarios

### High CPU Usage
```powershell
# Monitor top CPU consumers
.\Watch-Process.ps1 -SortBy CPU -Top 10 -RefreshInterval 5
```

### Memory Leak Investigation
```powershell
# Track memory growth
.\Get-ProcessMemory.ps1 -ProcessName "application" -Continuous -Interval 60
```

### Event Log Analysis
```powershell
# Find error patterns
.\Manage-EventLog.ps1 -LogName Application -Level Error -StartTime (Get-Date).AddDays(-1)
```

## Best Practices

1. **Run as Administrator**: Most diagnostics require elevated privileges
2. **Minimize Impact**: Use appropriate sampling intervals
3. **Baseline First**: Establish normal behavior before troubleshooting
4. **Correlate Data**: Use timestamps to correlate events across tools
5. **Clean Up**: Remove traces and logs after analysis

## Output Formats

Scripts support multiple output formats:
- **Console**: Interactive display with color coding
- **CSV**: Import into Excel or Power BI
- **JSON**: Structured data for automation
- **ETL**: Native Windows trace format

## Performance Impact

| Tool | Impact | Use When |
|------|--------|----------|
| Performance Counters | Low | Continuous monitoring |
| Process Monitor | Medium-High | Detailed investigation |
| .NET Trace | Medium | Application-specific issues |
| ETL Traces | Low-Medium | Network/kernel events |

## Related Documentation

- [Windows Performance Monitor](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/perfmon)
- [ETL Tracing](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/event-tracing-for-windows--etw-)
- [Process Monitor](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon)
- [dotnet-trace](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace)

## Testing

```powershell
Invoke-Pester -Path ..\..\tests\powershell\*Diagnostics*.Tests.ps1
```
