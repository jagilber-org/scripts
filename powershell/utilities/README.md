# Utility Scripts

This directory contains 56 general-purpose PowerShell scripts organized by functional area.

## Categories

### File Operations (10 scripts)
File management, comparison, and manipulation
- **Copy-FileWithProgress.ps1** - Copy files with progress bar and ETA
- **Split-File.ps1** - Split large files into chunks
- **Merge-File.ps1** - Combine split files back together
- **Compare-FileContent.ps1** - Deep comparison of file contents
- **Get-FileHash.ps1** - Calculate file hash (MD5, SHA1, SHA256)
- **Watch-FileChange.ps1** - Monitor directory for file changes
- **Compress-Directory.ps1** - Create ZIP archives with filtering
- **Expand-Archive.ps1** - Extract ZIP files with progress
- **Remove-OldFile.ps1** - Clean up files older than specified age
- **Search-FileContent.ps1** - PowerShell grep with regex support

### Certificate Management (4 scripts)
SSL/TLS certificate utilities
- **Get-CertificateMachineKey.ps1** - Locate certificate private key files
- **New-TestCertificate.ps1** - Generate self-signed certificates for testing
- **Convert-PfxToPem.ps1** - Convert PFX to PEM format
- **Test-CertificateChain.ps1** - Validate certificate chain and expiration

### Network Tools (8 scripts)
Network testing and monitoring
- **Test-HttpListener.ps1** - Test HTTP endpoint availability
- **Test-TcpListener.ps1** - Check TCP port connectivity
- **Watch-NetworkPort.ps1** - Monitor port state changes
- **Get-NetworkTrace.ps1** - Capture network traffic
- **Measure-NetworkLatency.ps1** - Ping and measure RTT
- **Test-DnsResolution.ps1** - DNS lookup and validation
- **Get-PublicIpAddress.ps1** - Retrieve external IP address
- **Test-UrlRedirection.ps1** - Follow HTTP redirects

### Development Tools (10 scripts)
Developer utilities and setup
- **Install-GitClient.ps1** - Download and install Git
- **Get-GitRelease.ps1** - Fetch GitHub release information
- **Start-DeveloperPrompt.ps1** - Launch Visual Studio Developer Command Prompt
- **Format-Json.ps1** - Pretty-print and validate JSON
- **Format-Xml.ps1** - Format and validate XML documents
- **Convert-JsonToYaml.ps1** - Convert between JSON and YAML
- **New-Guid.ps1** - Generate GUIDs/UUIDs
- **Encode-Base64.ps1** - Base64 encode/decode strings and files
- **Test-JsonSchema.ps1** - Validate JSON against schema
- **Get-ApiResponse.ps1** - Test REST API endpoints

### RDS Tools (9 scripts)
Remote Desktop Services management
- **Test-RdsLicenseServer.ps1** - Check RDS licensing server status
- **Get-RdsPerDeviceLicense.ps1** - Enumerate per-device CALs
- **Manage-RdsUserProfile.ps1** - User profile management for RDS
- **Get-RdsSession.ps1** - List active RDS sessions
- **Disconnect-RdsSession.ps1** - Disconnect user sessions
- **Send-RdsMessage.ps1** - Send messages to RDS users
- **Export-RdsConfiguration.ps1** - Backup RDS configuration
- **Import-RdsConfiguration.ps1** - Restore RDS configuration
- **Get-RdsConnectionStatus.ps1** - Monitor RDS connections

### Registry Management (2 scripts)
Windows Registry utilities
- **Get-RegistryPermission.ps1** - View registry key ACLs
- **Set-RegistryPermission.ps1** - Modify registry permissions

### Miscellaneous (13 scripts)
Various utility scripts
- **Convert-StringEncoding.ps1** - Convert text encoding (UTF-8, ASCII, Unicode)
- **Get-TimeDifference.ps1** - Calculate time span between dates
- **Get-SystemInfo.ps1** - Collect comprehensive system information
- **Test-Administrator.ps1** - Check if running with admin rights
- **Start-ElevatedProcess.ps1** - Launch process as administrator
- **Get-InstalledSoftware.ps1** - List installed applications
- **Remove-EmptyDirectory.ps1** - Clean up empty folders
- **New-RandomPassword.ps1** - Generate secure random passwords
- **Test-Port.ps1** - Simple port connectivity test
- **Get-FolderSize.ps1** - Calculate directory size recursively
- **Export-Credential.ps1** - Securely store credentials
- **Import-Credential.ps1** - Retrieve stored credentials
- **ConvertTo-HumanReadableSize.ps1** - Format bytes as KB/MB/GB

## Prerequisites

### PowerShell Version
- PowerShell 5.1 or higher recommended
- Some scripts support PowerShell Core 6+

### Common Modules
```powershell
# Certificate management
Import-Module PKI

# Network utilities (built-in)
# File operations (built-in)
```

## Common Use Cases

### File Operations

**Copy with Progress**
```powershell
.\Copy-FileWithProgress.ps1 -Source "C:\Large\File.iso" -Destination "D:\Backup\" -ShowProgress
```

**Search Files (PowerShell grep)**
```powershell
.\Search-FileContent.ps1 -Path "C:\Logs" -Pattern "error|exception" -Recurse -IgnoreCase
```

**Split and Merge Large Files**
```powershell
# Split 10GB file into 1GB chunks
.\Split-File.ps1 -FilePath "C:\Data\large.zip" -ChunkSizeMB 1024

# Merge back together
.\Merge-File.ps1 -FilePath "C:\Data\large.zip.part001" -OutputPath "C:\Data\restored.zip"
```

### Certificate Management

**Generate Test Certificate**
```powershell
.\New-TestCertificate.ps1 `
    -DnsName "*.contoso.com", "contoso.com" `
    -OutputPath "C:\Certs\test.pfx" `
    -Password "P@ssw0rd" `
    -ValidYears 1
```

**Locate Certificate Private Key**
```powershell
.\Get-CertificateMachineKey.ps1 -Thumbprint "A1B2C3D4E5F67890..."
```

**Convert PFX to PEM**
```powershell
.\Convert-PfxToPem.ps1 -PfxFile "C:\Certs\cert.pfx" -Password "P@ssw0rd" -OutputPath "C:\Certs\"
# Produces: cert.crt, cert.key
```

### Network Tools

**Test HTTP Endpoint**
```powershell
.\Test-HttpListener.ps1 -Url "https://api.contoso.com/health" -ExpectedStatusCode 200 -Timeout 30
```

**Monitor Port**
```powershell
.\Watch-NetworkPort.ps1 -ComputerName "server01" -Port 443 -CheckInterval 10 -AlertOnChange
```

**Measure Latency**
```powershell
.\Measure-NetworkLatency.ps1 -Target "8.8.8.8" -Count 100 | Measure-Object Latency -Average -Minimum -Maximum
```

### Development Tools

**Format JSON**
```powershell
Get-Content "ugly.json" -Raw | .\Format-Json.ps1 | Set-Content "pretty.json"
```

**Generate GUIDs**
```powershell
# Generate 10 GUIDs
1..10 | ForEach-Object { .\New-Guid.ps1 }
```

**Test REST API**
```powershell
.\Get-ApiResponse.ps1 `
    -Url "https://api.github.com/users/octocat" `
    -Method GET `
    -Headers @{ "Accept" = "application/vnd.github.v3+json" }
```

### RDS Management

**Check License Server**
```powershell
.\Test-RdsLicenseServer.ps1 -LicenseServer "rds-lic-01.contoso.com"
```

**List Active Sessions**
```powershell
.\Get-RdsSession.ps1 -ComputerName "rds-host-01" | Format-Table UserName, SessionState, ConnectTime
```

**Send Message to Users**
```powershell
.\Send-RdsMessage.ps1 -ComputerName "rds-host-01" -SessionId 2 -Message "Server will restart in 5 minutes" -Title "Maintenance"
```

### Registry Management

**View Registry Permissions**
```powershell
.\Get-RegistryPermission.ps1 -Path "HKLM:\SOFTWARE\MyApp"
```

**Set Registry ACL**
```powershell
.\Set-RegistryPermission.ps1 -Path "HKLM:\SOFTWARE\MyApp" -User "DOMAIN\AppUser" -Rights FullControl
```

### Miscellaneous Utilities

**Generate Secure Password**
```powershell
.\New-RandomPassword.ps1 -Length 16 -IncludeSymbols -IncludeNumbers
```

**Get Folder Size**
```powershell
.\Get-FolderSize.ps1 -Path "C:\Users" -Recurse | Sort-Object SizeGB -Descending | Select-Object -First 10
```

**Human-Readable File Sizes**
```powershell
Get-ChildItem C:\Data | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Size = .\ConvertTo-HumanReadableSize.ps1 -Bytes $_.Length
    }
}
```

**Store Credentials Securely**
```powershell
# Export
$cred = Get-Credential
.\Export-Credential.ps1 -Credential $cred -Path "C:\Secure\cred.xml"

# Import
$cred = .\Import-Credential.ps1 -Path "C:\Secure\cred.xml"
```

## Performance Tips

### File Operations
- Use `-Buffer` parameter for large file copies
- Enable `-Async` for parallel file operations
- Filter with `-Include`/`-Exclude` before processing

### Network Tools
- Set appropriate timeouts for unreliable networks
- Use `-Parallel` for testing multiple endpoints
- Cache DNS lookups when testing repeatedly

### Certificate Operations
- Certificate store queries can be slow; cache results
- Use `-Thumbprint` for fast certificate lookup
- Export to PEM once; import is expensive

## Security Best Practices

### Credentials
```powershell
# NEVER hardcode credentials
$cred = Get-Credential

# Use credential manager
$cred = .\Import-Credential.ps1 -Path "$env:USERPROFILE\.creds\app.xml"

# For automation, use managed identity or Key Vault
```

### File Operations
```powershell
# Validate paths before operations
if (Test-Path $path) {
    # Ensure within allowed directory
    $resolvedPath = Resolve-Path $path
    if ($resolvedPath.Path.StartsWith("C:\AllowedDir")) {
        # Safe to proceed
    }
}
```

### Network Calls
```powershell
# Always use HTTPS for production
# Validate certificates
.\Test-HttpListener.ps1 -Url "https://api.contoso.com" -ValidateCertificate

# Set timeouts to prevent hanging
.\Get-ApiResponse.ps1 -Url $url -Timeout 30
```

## Error Handling Patterns

### Try-Catch with Retry
```powershell
$maxRetries = 3
$retryDelay = 5

for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        .\Test-HttpListener.ps1 -Url $url
        break
    } catch {
        if ($i -eq $maxRetries - 1) {
            throw
        }
        Write-Warning "Attempt $($i + 1) failed. Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
    }
}
```

### Graceful Degradation
```powershell
try {
    $result = .\Get-ApiResponse.ps1 -Url $primaryUrl
} catch {
    Write-Warning "Primary endpoint failed. Trying fallback..."
    $result = .\Get-ApiResponse.ps1 -Url $fallbackUrl
}
```

## Output Formats

Most scripts support multiple output formats:

```powershell
# Object output (default)
$result = .\Get-SystemInfo.ps1

# JSON
.\Get-SystemInfo.ps1 | ConvertTo-Json -Depth 5

# CSV
.\Get-SystemInfo.ps1 | Export-Csv -Path "system-info.csv" -NoTypeInformation

# Table
.\Get-SystemInfo.ps1 | Format-Table -AutoSize
```

## Integration Examples

### Pipeline Usage
```powershell
# Find large log files and compress
Get-ChildItem C:\Logs -Recurse -Filter "*.log" |
    Where-Object { $_.Length -gt 100MB } |
    ForEach-Object {
        .\Compress-Directory.ps1 -Path $_.FullName -OutputPath "$($_.FullName).zip" -DeleteOriginal
    }
```

### Scheduled Task Integration
```powershell
# Clean up old files daily
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Scripts\Remove-OldFile.ps1 -Path C:\Temp -DaysOld 30"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "CleanupOldFiles" -Action $action -Trigger $trigger
```

### Monitoring Integration
```powershell
# Export metrics to monitoring system
$metrics = @{
    DiskSpace = (Get-PSDrive C | Select-Object -ExpandProperty Free)
    ProcessCount = (Get-Process | Measure-Object).Count
    UploadLatency = (.\Measure-NetworkLatency.ps1 -Target "upload.contoso.com").Latency
}

$metrics | ConvertTo-Json | .\Get-ApiResponse.ps1 -Url "https://metrics.contoso.com/api/publish" -Method POST
```

## Troubleshooting

### Script Won't Execute
```powershell
# Check execution policy
Get-ExecutionPolicy

# Set for current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Module Not Found
```powershell
# List available modules
Get-Module -ListAvailable

# Import module
Import-Module ModuleName

# Install from PowerShell Gallery
Install-Module -Name ModuleName -Scope CurrentUser
```

### Access Denied
```powershell
# Check if admin required
.\Test-Administrator.ps1

# Run as administrator
.\Start-ElevatedProcess.ps1 -FilePath "powershell.exe" -Arguments "-File C:\Scripts\MyScript.ps1"
```

## Related Documentation

- [PowerShell Documentation](https://learn.microsoft.com/en-us/powershell/)
- [Certificate Management](https://learn.microsoft.com/en-us/powershell/module/pki/)
- [Remote Desktop Services](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/)
- [Windows Registry](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry)

## Testing

```powershell
# Run all utility tests
Invoke-Pester -Path ..\..\tests\powershell\*Utility*.Tests.ps1

# Test specific category
Invoke-Pester -Path ..\..\tests\powershell\Search-FileContent.Tests.ps1 -Output Detailed
```

## Contributing

When adding new utility scripts:
1. Follow [PowerShell Verb-Noun naming](../../docs/NAMING-CONVENTIONS.md)
2. Include comment-based help with examples
3. Add parameter validation
4. Write Pester tests
5. Update this README with usage examples
