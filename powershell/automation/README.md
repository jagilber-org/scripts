# Automation & Scheduling Scripts

This directory contains 5 PowerShell scripts for task automation, parallel processing, and system orchestration.

## Scripts

### Task Scheduling
- **New-ScheduledTask.ps1** - Create and configure Windows scheduled tasks programmatically

### Parallel Execution
- **Start-ParallelJob.ps1** - Execute PowerShell jobs in parallel with throttling and progress

### Hyper-V Automation
- **Watch-HyperVVm.ps1** - Monitor Hyper-V virtual machine state and trigger actions

### Environment Management
- **Import-EnvironmentFile.ps1** - Load environment variables from .env files
- **Resolve-EnvironmentPath.ps1** - Expand environment variables in paths and strings

## Common Use Cases

### Create Scheduled Task
```powershell
# Daily cleanup task
.\New-ScheduledTask.ps1 `
    -TaskName "DailyLogCleanup" `
    -Description "Clean up old log files" `
    -ScriptPath "C:\Scripts\Cleanup-Logs.ps1" `
    -Trigger Daily `
    -StartTime "02:00:00" `
    -RunAsUser "SYSTEM"
```

### Parallel Processing
```powershell
# Process multiple servers in parallel
$servers = Get-Content "servers.txt"

.\Start-ParallelJob.ps1 `
    -InputObject $servers `
    -ScriptBlock {
        param($server)
        Test-Connection -ComputerName $server -Count 1
        Invoke-Command -ComputerName $server -ScriptBlock { Get-Service }
    } `
    -ThrottleLimit 10 `
    -ShowProgress
```

### Monitor Hyper-V VMs
```powershell
# Watch VM state and restart if stopped
.\Watch-HyperVVm.ps1 `
    -VMName "WebServer01" `
    -CheckInterval 60 `
    -Action {
        param($vm)
        if ($vm.State -eq 'Off') {
            Start-VM -Name $vm.Name
            Send-MailMessage -To admin@company.com -Subject "VM Restarted" -Body "VM $($vm.Name) was restarted"
        }
    }
```

### Load Environment Variables
```powershell
# Import .env file for application config
.\Import-EnvironmentFile.ps1 -Path "C:\Apps\MyApp\.env"

# Access loaded variables
$dbConnectionString = $env:DB_CONNECTION_STRING
$apiKey = $env:API_KEY
```

### Expand Environment Paths
```powershell
# Resolve paths with environment variables
.\Resolve-EnvironmentPath.ps1 -Path "%USERPROFILE%\Documents\MyApp"
# Output: C:\Users\username\Documents\MyApp

# Multiple paths
$paths = @("%TEMP%\logs", "%APPDATA%\config")
$resolved = $paths | .\Resolve-EnvironmentPath.ps1
```

## Prerequisites

### PowerShell Version
- PowerShell 5.1 or higher
- Windows PowerShell or PowerShell Core

### Required Modules
```powershell
# For scheduled tasks
Import-Module ScheduledTasks

# For Hyper-V monitoring
Import-Module Hyper-V
```

### Administrator Rights
Most automation tasks require elevation:
```powershell
# Check if running as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script requires administrator privileges"
}
```

## Scheduled Task Patterns

### Daily Execution
```powershell
.\New-ScheduledTask.ps1 `
    -TaskName "BackupDatabase" `
    -ScriptPath "C:\Scripts\Backup-DB.ps1" `
    -Trigger Daily `
    -StartTime "23:00:00" `
    -RunAsUser "DOMAIN\ServiceAccount"
```

### On System Startup
```powershell
.\New-ScheduledTask.ps1 `
    -TaskName "InitializeServices" `
    -ScriptPath "C:\Scripts\Start-Services.ps1" `
    -Trigger AtStartup `
    -RunAsUser "SYSTEM"
```

### On Event Trigger
```powershell
.\New-ScheduledTask.ps1 `
    -TaskName "HandleError" `
    -ScriptPath "C:\Scripts\Handle-Error.ps1" `
    -Trigger OnEvent `
    -EventLog "Application" `
    -EventId 1000 `
    -RunAsUser "SYSTEM"
```

### Multiple Schedules
```powershell
# Run at 9 AM and 5 PM weekdays
.\New-ScheduledTask.ps1 `
    -TaskName "DailyReport" `
    -ScriptPath "C:\Scripts\Generate-Report.ps1" `
    -Trigger @(
        @{ Type = 'Daily'; Time = '09:00:00'; DaysOfWeek = 'Monday,Tuesday,Wednesday,Thursday,Friday' },
        @{ Type = 'Daily'; Time = '17:00:00'; DaysOfWeek = 'Monday,Tuesday,Wednesday,Thursday,Friday' }
    )
```

## Parallel Processing Patterns

### Throttled Execution
```powershell
# Process 100 items with max 20 concurrent jobs
$items = 1..100

.\Start-ParallelJob.ps1 `
    -InputObject $items `
    -ScriptBlock {
        param($item)
        # Simulate work
        Start-Sleep -Seconds (Get-Random -Minimum 1 -Maximum 5)
        return "Processed item $item"
    } `
    -ThrottleLimit 20 `
    -ShowProgress
```

### With Error Handling
```powershell
.\Start-ParallelJob.ps1 `
    -InputObject $servers `
    -ScriptBlock {
        param($server)
        try {
            Invoke-Command -ComputerName $server -ScriptBlock { Get-Service } -ErrorAction Stop
        } catch {
            Write-Warning "Failed to connect to $server: $_"
            return $null
        }
    } `
    -ThrottleLimit 10 `
    -ContinueOnError
```

### Collect Results
```powershell
$results = .\Start-ParallelJob.ps1 `
    -InputObject $servers `
    -ScriptBlock {
        param($server)
        [PSCustomObject]@{
            Server = $server
            Online = Test-Connection -ComputerName $server -Count 1 -Quiet
            Services = (Get-Service -ComputerName $server | Measure-Object).Count
        }
    } `
    -ThrottleLimit 15

$results | Export-Csv -Path "server-status.csv" -NoTypeInformation
```

## Hyper-V Monitoring Patterns

### VM State Monitoring
```powershell
# Monitor and log VM state changes
.\Watch-HyperVVm.ps1 `
    -VMName "ProductionDB" `
    -CheckInterval 30 `
    -Action {
        param($vm)
        Add-Content -Path "C:\Logs\vm-state.log" -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - VM: $($vm.Name), State: $($vm.State)"
    }
```

### Automatic Recovery
```powershell
# Restart VM if stopped unexpectedly
.\Watch-HyperVVm.ps1 `
    -VMName "WebServer*" `
    -CheckInterval 60 `
    -Action {
        param($vm)
        if ($vm.State -eq 'Off' -and $vm.Uptime -lt [TimeSpan]::FromMinutes(5)) {
            Write-Warning "VM $($vm.Name) stopped unexpectedly. Restarting..."
            Start-VM -Name $vm.Name
        }
    }
```

### Resource Alerting
```powershell
.\Watch-HyperVVm.ps1 `
    -VMName "AppServer" `
    -CheckInterval 120 `
    -Action {
        param($vm)
        $cpu = (Get-VMProcessor -VMName $vm.Name).PercentComplete
        if ($cpu -gt 90) {
            Send-AlertEmail -Subject "High CPU on $($vm.Name)" -Body "CPU usage: $cpu%"
        }
    }
```

## Environment File Patterns

### .env File Format
```ini
# Database configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp
DB_USER=admin
DB_PASSWORD=SecureP@ssw0rd

# API Keys
API_KEY=abc123xyz789
SECRET_KEY=super-secret-key

# Feature flags
ENABLE_FEATURE_X=true
MAX_CONNECTIONS=100
```

### Load and Use Variables
```powershell
# Load environment from .env file
.\Import-EnvironmentFile.ps1 -Path "C:\Apps\MyApp\.env"

# Use in connection string
$connectionString = "Server=$env:DB_HOST;Port=$env:DB_PORT;Database=$env:DB_NAME;User=$env:DB_USER;Password=$env:DB_PASSWORD"

# Use in API client
$headers = @{
    "Authorization" = "Bearer $env:API_KEY"
    "X-Secret-Key" = $env:SECRET_KEY
}
```

### Multiple Environments
```powershell
# Load different configs per environment
$environment = $env:ENVIRONMENT ?? "Development"

switch ($environment) {
    "Development" { .\Import-EnvironmentFile.ps1 -Path "C:\Config\.env.dev" }
    "Staging" { .\Import-EnvironmentFile.ps1 -Path "C:\Config\.env.staging" }
    "Production" { .\Import-EnvironmentFile.ps1 -Path "C:\Config\.env.prod" }
}
```

## Path Resolution Patterns

### Expand Variables
```powershell
# Single path
$expanded = .\Resolve-EnvironmentPath.ps1 -Path "%APPDATA%\MyApp\config.json"

# Multiple paths
$paths = @(
    "%TEMP%\logs\*.log",
    "%PROGRAMFILES%\MyApp\bin",
    "%USERPROFILE%\Documents\Reports"
)
$resolved = $paths | .\Resolve-EnvironmentPath.ps1
```

### Validate Expanded Paths
```powershell
$path = .\Resolve-EnvironmentPath.ps1 -Path "%SYSTEMROOT%\System32"
if (Test-Path $path) {
    Get-ChildItem $path
} else {
    Write-Error "Path does not exist: $path"
}
```

## Performance Considerations

### Parallel Jobs
- **ThrottleLimit**: Balance between parallelism and system resources
- **Job Overhead**: PowerShell jobs have initialization cost (~100ms each)
- **Memory**: Each job consumes memory; monitor with `Get-Process powershell`

### Scheduled Tasks
- **Task Scheduler Limits**: Windows supports thousands of tasks but check performance
- **Overlap Prevention**: Use `-ExecutionTimeLimit` to prevent task overlap
- **Priority**: Set task priority to avoid impacting interactive users

### Hyper-V Monitoring
- **Polling Interval**: Balance between responsiveness and CPU usage
- **WMI Queries**: Hyper-V cmdlets use WMI; cache results when possible
- **Remote Monitoring**: Use `-ComputerName` parameter for remote hosts

## Best Practices

1. **Error Handling**: Always use try/catch in parallel scriptblocks
2. **Logging**: Log all automation actions for audit and troubleshooting
3. **Credentials**: Use Credential Manager or Key Vault, never hardcode
4. **Testing**: Test scheduled tasks manually before deploying
5. **Monitoring**: Alert on task failures and unexpected behavior
6. **Idempotency**: Design tasks to be safely re-runnable

## Security Considerations

- Run scheduled tasks with least privilege accounts
- Store sensitive data in .env files outside web roots
- Use encrypted credentials with `Export-Clixml` for automation
- Audit scheduled task execution with Event Log (Event ID 4698, 4699, 4700, 4701)
- Restrict .env file permissions to prevent unauthorized access

## Troubleshooting

### Scheduled Task Not Running
```powershell
# Check task status
Get-ScheduledTask -TaskName "MyTask" | Get-ScheduledTaskInfo

# View task history
Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" | 
    Where-Object { $_.Message -like "*MyTask*" }
```

### Parallel Job Hangs
```powershell
# Check running jobs
Get-Job | Where-Object { $_.State -eq 'Running' }

# Stop hung jobs
Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
```

### Hyper-V Module Not Loading
```powershell
# Enable Hyper-V PowerShell module
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell
```

## Related Documentation

- [Task Scheduler](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
- [PowerShell Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_jobs)
- [Hyper-V Cmdlets](https://learn.microsoft.com/en-us/powershell/module/hyper-v/)
- [Environment Variables](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables)

## Testing

```powershell
Invoke-Pester -Path ..\..\tests\powershell\*Automation*.Tests.ps1
```
