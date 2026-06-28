# Data Collection & Query Scripts

This directory contains 8 PowerShell scripts for data collection, querying, and log processing.

## Scripts

### Azure Data Explorer (Kusto)
- **Invoke-KustoQuery.ps1** - Execute KQL queries against Kusto clusters
- **Invoke-KustoQueryV2.ps1** - Enhanced Kusto query execution with retry logic
- **Install-KustoEmulator.ps1** - Install and configure local Kusto emulator for testing

### Log Processing
- **Merge-LogFile.ps1** - Merge multiple log files with timestamp sorting
- **Merge-PowerShellLog.ps1** - Combine PowerShell transcripts and logs

### WMI/CIM Enumeration
- **Get-WmiClass.ps1** - Discover and enumerate WMI classes and properties
- **Get-CimClass.ps1** - Query CIM classes (modern WMI replacement)

### Event Log Metadata
- **Get-EventLogMetadata.ps1** - Extract event log schema and provider information

## Common Use Cases

### Query Kusto/Azure Data Explorer
```powershell
# Execute KQL query
.\Invoke-KustoQuery.ps1 `
    -ClusterUri "https://mycluster.kusto.windows.net" `
    -Database "MyDatabase" `
    -Query "MyTable | where Timestamp > ago(1h) | summarize count() by Category"
```

### Merge Service Fabric Logs
```powershell
# Combine multiple trace files with timestamp sorting
.\Merge-LogFile.ps1 `
    -InputPath "C:\Logs\*.trace" `
    -OutputFile "C:\Logs\merged.log" `
    -TimestampPattern "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+"
```

### Enumerate WMI Classes
```powershell
# Find all Win32 classes
.\Get-WmiClass.ps1 -Namespace "root\cimv2" -Filter "Win32_*"

# Get class properties
.\Get-CimClass.ps1 -ClassName "Win32_Process" -ShowProperties
```

### Extract Event Log Schema
```powershell
# Get event provider metadata
.\Get-EventLogMetadata.ps1 -LogName "Application" -ProviderName "MyApp"
```

## Prerequisites

### Kusto Client Library
```powershell
Install-Package Microsoft.Azure.Kusto.Tools -Source https://www.nuget.org/api/v2
```

### Azure Authentication
```powershell
# Interactive authentication
.\Invoke-KustoQuery.ps1 -ClusterUri "https://cluster.kusto.windows.net" -Database "db" -UseDeviceAuth

# Service principal
.\Invoke-KustoQuery.ps1 `
    -ClusterUri "https://cluster.kusto.windows.net" `
    -Database "db" `
    -ApplicationId "app-id" `
    -ApplicationKey "app-secret" `
    -TenantId "tenant-id"
```

## Kusto Query Language (KQL) Examples

### Time-Based Filtering
```kql
MyTable
| where Timestamp > ago(24h)
| summarize count() by bin(Timestamp, 1h)
```

### Text Search
```kql
MyTable
| where Message contains "error" or Message contains "exception"
| project Timestamp, Level, Message
| order by Timestamp desc
```

### Aggregation
```kql
MyTable
| summarize 
    Count=count(),
    AvgDuration=avg(Duration),
    P95=percentile(Duration, 95)
    by Category
```

### Join Operations
```kql
Events
| join kind=inner (Alerts) on CorrelationId
| project Timestamp, Event=Events.Name, Alert=Alerts.Severity
```

## Log Merging Patterns

### Timestamp-Based Merge
```powershell
# Merge with common timestamp format
.\Merge-LogFile.ps1 `
    -InputPath "C:\Logs\node-*.log" `
    -OutputFile "C:\Logs\cluster-merged.log" `
    -TimestampPattern "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z" `
    -SortChronologically
```

### PowerShell Transcript Merge
```powershell
# Combine multiple PowerShell session logs
.\Merge-PowerShellLog.ps1 `
    -Path "C:\Transcripts\*.txt" `
    -Output "C:\Transcripts\combined.txt" `
    -IncludeHeaders
```

## WMI/CIM Query Patterns

### Query with Filtering
```powershell
# Get running processes over 100MB
Get-CimInstance -ClassName Win32_Process |
    Where-Object { $_.WorkingSetSize -gt 100MB } |
    Select-Object Name, ProcessId, WorkingSetSize
```

### Remote Query
```powershell
.\Get-CimClass.ps1 -ClassName "Win32_Service" -ComputerName "Server01" -Filter "State='Running'"
```

### WMI Namespace Exploration
```powershell
# List all classes in namespace
.\Get-WmiClass.ps1 -Namespace "root\microsoft\windows\storage" -ListAll
```

## Kusto Emulator Setup

### Install and Configure
```powershell
# Install emulator for local testing
.\Install-KustoEmulator.ps1 -InstallPath "C:\KustoEmulator"

# Create test database
.\Invoke-KustoQuery.ps1 -ClusterUri "http://localhost:8080" -Database "master" -Query ".create database TestDB"

# Ingest test data
.\Invoke-KustoQuery.ps1 -ClusterUri "http://localhost:8080" -Database "TestDB" -Query @"
.create table Logs (Timestamp:datetime, Level:string, Message:string)
.ingest inline into table Logs <|
2025-01-01T10:00:00Z,Info,Application started
2025-01-01T10:01:00Z,Error,Connection failed
"@
```

## Authentication Methods

### Interactive (Device Code)
Best for development and manual queries:
```powershell
.\Invoke-KustoQuery.ps1 -ClusterUri $uri -Database $db -UseDeviceAuth
```

### Service Principal
Best for automation and CI/CD:
```powershell
.\Invoke-KustoQuery.ps1 `
    -ClusterUri $uri `
    -Database $db `
    -ApplicationId $appId `
    -ApplicationKey $secret `
    -TenantId $tenantId
```

### Managed Identity
Best for Azure resources (VMs, App Service):
```powershell
.\Invoke-KustoQuery.ps1 -ClusterUri $uri -Database $db -UseManagedIdentity
```

## Performance Considerations

### Query Optimization
- Use `where` before `project` to filter early
- Limit result sets with `take` or `top`
- Use `summarize` for aggregation instead of post-processing
- Create materialized views for frequently accessed data

### Log Merging
- Process large files in chunks
- Use streaming when possible
- Consider parallel processing for multiple files
- Sort only when necessary (expensive operation)

### WMI/CIM
- Use CIM cmdlets over WMI (faster, more reliable)
- Filter on server side with `-Filter` parameter
- Select only needed properties to reduce network traffic
- Use `-ErrorAction SilentlyContinue` for unreliable remote systems

## Output Formats

### Kusto Results
- **JSON**: `-OutputFormat JSON` for automation
- **CSV**: `-OutputFormat CSV` for Excel import
- **Table**: Default console output

### Log Files
- **Plain Text**: Standard merged logs
- **JSON Lines**: One JSON object per line
- **XML**: Structured event logs

## Error Handling

### Retry Logic (Invoke-KustoQueryV2.ps1)
```powershell
.\Invoke-KustoQueryV2.ps1 `
    -ClusterUri $uri `
    -Database $db `
    -Query $query `
    -MaxRetries 3 `
    -RetryDelaySeconds 5
```

### Connection Failures
- Check cluster URI format: `https://cluster.region.kusto.windows.net`
- Verify firewall rules allow Kusto ports (443)
- Ensure authentication credentials are valid
- Check database permissions (viewer role minimum)

## Best Practices

1. **Parameterize Queries**: Use parameters instead of string concatenation
2. **Limit Results**: Always use `take` or `top` for exploratory queries
3. **Cache Results**: Store frequently accessed data locally
4. **Monitor Costs**: Track query complexity and data scanned
5. **Version Control**: Store KQL queries in source control

## Security Considerations

- Never hardcode credentials in scripts
- Use Key Vault for secrets management
- Prefer managed identity over service principals
- Apply least privilege (viewer role for read-only queries)
- Audit query execution for compliance

## Related Documentation

- [Kusto Query Language](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Azure Data Explorer](https://learn.microsoft.com/en-us/azure/data-explorer/)
- [WMI Reference](https://learn.microsoft.com/en-us/windows/win32/wmisdk/wmi-start-page)
- [CIM Cmdlets](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/)

## Testing

```powershell
Invoke-Pester -Path ..\..\tests\powershell\Invoke-Kusto*.Tests.ps1
```
