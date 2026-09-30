# Service Fabric Management Scripts

This directory contains 44 PowerShell scripts for Azure Service Fabric cluster management, diagnostics, deployment, and monitoring.

## Scripts by Category

### Azure Resource Management (11 scripts)
Azure-level Service Fabric operations
- **Export-ServiceFabricArmTemplate.ps1** - Export cluster ARM template
- **Get-ServiceFabricImageStore.ps1** - Enumerate fabric image store contents
- **Find-ServiceFabricNodeType.ps1** - Locate node type configuration
- **Repair-ServiceFabricUpgradeDomain.ps1** - Fix upgrade domain issues
- **Set-ServiceFabricImageStoreSettings.ps1** - Configure image store settings
- **Set-ServiceFabricSettings.ps1** - Update fabric settings
- **Test-ServiceFabricManagedIdentity.ps1** - Validate managed identity token service
- **Get-ServiceFabricRdpPort.ps1** - Get RDP port from load balancer
- **Remove-ServiceFabricApplication.ps1** - Remove application from cluster
- **Invoke-ServiceFabricRestQuery.ps1** - Execute REST API queries
- **Test-ServiceFabricNodeTypeScaling.ps1** - Test node type scaling operations

### Cluster Operations (14 scripts)
Cluster connectivity and management
- **Connect-ServiceFabricCluster.ps1** - Connect to cluster with authentication
- **Get-ServiceFabricQuickStatus.ps1** - Quick cluster health overview
- **Invoke-ServiceFabricRestApi.ps1** - REST API client for SF operations
- **Disable-ServiceFabricNode.ps1** - Gracefully disable cluster node
- **Start-ServiceFabricClusterUpgradeReboot.ps1** - Orchestrate upgrade with reboots
- **Convert-ServiceFabricEtl.ps1** - Parse and convert ETL trace files
- **New-ServiceFabricDevClusterSecure.ps1** - Create secure development cluster
- **Get-ServiceFabricCab.ps1** - Download Service Fabric CAB packages
- **Get-ServiceFabricArmApplications.ps1** - Enumerate ARM-deployed applications
- **Get-ServiceFabricMetadata.ps1** - Query cluster metadata via REST
- **Invoke-ServiceFabricHttpClient.ps1** - HTTP client for SF endpoints
- **Install-ServiceFabricSdk.ps1** - Install Service Fabric SDK
- **Restart-ServiceFabricWarningReplicas.ps1** - Restart replicas in warning state
- **Update-ServiceFabricStandaloneManifest.ps1** - Update standalone cluster manifest

### Docker/Container Operations (6 scripts)
Container orchestration on Service Fabric
- **Get-ServiceFabricDockerLog.ps1** - Retrieve Docker container logs
- **Watch-ServiceFabricDocker.ps1** - Monitor Docker containers
- **Connect-ServiceFabricDockerNamedPipe.ps1** - Connect to Docker named pipe
- **Watch-ServiceFabricDockerPlugin.ps1** - Monitor Service Fabric Docker plugin
- **Remove-ServiceFabricDockerPlugin.ps1** - Uninstall Docker plugin
- **Clear-ServiceFabricDocker.ps1** - Prune unused Docker resources

### Tracing & Diagnostics (5 scripts)
ETL tracing and diagnostic collection
- **Start-ServiceFabricAutoTracing.ps1** - Automatic ETL trace collection
- **Start-ServiceFabricEtlTracing.ps1** - Manual ETL tracing
- **Start-ServiceFabricHnsTracing.ps1** - Host Networking Service tracing
- **Start-ServiceFabricRealtimeTracing.ps1** - Real-time trace capture
- **Add-ServiceFabricRuntimeToImageStore.ps1** - Upload runtime to image store

### Managed Clusters (5 scripts)
Azure Service Fabric Managed Cluster operations
- **Connect-ServiceFabricManagedAdo.ps1** - Connect managed cluster to Azure DevOps
- **Set-ServiceFabricManagedApim.ps1** - Configure API Management integration
- **Connect-ServiceFabricManaged.ps1** - Connect to managed cluster
- **Deploy-ServiceFabricManaged.ps1** - Deploy to managed cluster
- **Update-ServiceFabricManagedPrimary.ps1** - Replace primary node type

### SFCTL & Linux (3 scripts)
Service Fabric CLI and Linux cluster support
- **Start-ServiceFabricChaos.ps1** - Start chaos test via sfctl
- **Connect-ServiceFabricCtl.ps1** - Connect using sfctl
- **Invoke-ServiceFabricLinuxRest.ps1** - REST API calls to Linux clusters

## Prerequisites

### Service Fabric SDK
```powershell
# Install SDK (required for most operations)
.\Install-ServiceFabricSdk.ps1

# Or download manually
# https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-get-started
```

### Azure PowerShell Module
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser
Install-Module -Name Az.ServiceFabric
```

### Service Fabric PowerShell Module
```powershell
# Installed with SDK, or install separately
Install-Module -Name ServiceFabric
```

### SFCTL (Service Fabric CLI)
```bash
# For SFCTL operations (Python-based)
pip install sfctl
```

## Authentication Methods

### Certificate-Based (Production)
```powershell
.\Connect-ServiceFabricCluster.ps1 `
    -ConnectionEndpoint "mycluster.eastus.cloudapp.azure.com:19000" `
    -X509Credential `
    -ServerCertThumbprint "ABCD1234..." `
    -FindType FindByThumbprint `
    -FindValue "EFGH5678..." `
    -StoreLocation CurrentUser `
    -StoreName My
```

### Azure AD (Interactive)
```powershell
.\Connect-ServiceFabricCluster.ps1 `
    -ConnectionEndpoint "mycluster.eastus.cloudapp.azure.com:19000" `
    -AzureActiveDirectory `
    -ServerCertThumbprint "ABCD1234..."
```

### Unsecured (Dev Only)
```powershell
.\Connect-ServiceFabricCluster.ps1 `
    -ConnectionEndpoint "localhost:19000"
```

## Common Use Cases

### Cluster Health & Status
```powershell
# Quick health overview
.\Get-ServiceFabricQuickStatus.ps1 -ConnectionEndpoint "mycluster.eastus.cloudapp.azure.com:19000"

# Detailed cluster metadata
.\Get-ServiceFabricMetadata.ps1 -ClusterUrl "https://mycluster.eastus.cloudapp.azure.com:19080"

# Check application health
.\Invoke-ServiceFabricRestApi.ps1 -Endpoint "https://mycluster:19080/Applications/MyApp/$/GetHealth"
```

### Diagnostics & Troubleshooting
```powershell
# Start real-time tracing
.\Start-ServiceFabricRealtimeTracing.ps1 -TraceLevel 4 -OutputPath "C:\Traces"

# Automatic trace collection on issues
.\Start-ServiceFabricAutoTracing.ps1 -TriggerOnError -MaxFileSize 1GB

# Convert collected ETL files
.\Convert-ServiceFabricEtl.ps1 -EtlPath "C:\Traces\fabric.etl" -OutputFormat CSV
```

### Application Deployment
```powershell
# Upload runtime to image store
.\Add-ServiceFabricRuntimeToImageStore.ps1 -RuntimeVersion "9.1.1436.9590"

# Deploy managed cluster application
.\Deploy-ServiceFabricManaged.ps1 `
    -ResourceGroup "MyRG" `
    -ClusterName "MyCluster" `
    -ApplicationPackage "C:\Apps\MyApp"
```

### Cluster Upgrades
```powershell
# Orchestrate cluster upgrade with node reboots
.\Start-ServiceFabricClusterUpgradeReboot.ps1 `
    -ConnectionEndpoint "mycluster:19000" `
    -TargetCodeVersion "9.1.1436.9590" `
    -UpgradeMode Monitored

# Repair stuck upgrade domain
.\Repair-ServiceFabricUpgradeDomain.ps1 -UpgradeDomain "UD2"
```

### Node Management
```powershell
# Disable node for maintenance
.\Disable-ServiceFabricNode.ps1 -NodeName "_NodeType0_2" -Intent Restart

# Restart warning replicas
.\Restart-ServiceFabricWarningReplicas.ps1 -NodeName "_NodeType0_2"
```

### Docker/Container Operations
```powershell
# Monitor Docker containers
.\Watch-ServiceFabricDocker.ps1 -RefreshInterval 5

# Collect Docker logs
.\Get-ServiceFabricDockerLog.ps1 -ContainerName "MyService_1" -OutputPath "C:\Logs"

# Connect to Docker named pipe
.\Connect-ServiceFabricDockerNamedPipe.ps1 -PipeName "docker_engine"

# Clean up unused containers/images
.\Clear-ServiceFabricDocker.ps1 -Force
```

### Managed Cluster Operations
```powershell
# Connect to managed cluster
.\Connect-ServiceFabricManaged.ps1 `
    -ResourceGroup "MyRG" `
    -ClusterName "MyManagedCluster"

# Configure API Management
.\Set-ServiceFabricManagedApim.ps1 `
    -ClusterName "MyManagedCluster" `
    -ApimServiceName "MyAPIM"

# Replace primary node type
.\Update-ServiceFabricManagedPrimary.ps1 `
    -ClusterName "MyManagedCluster" `
    -NewNodeTypeName "PrimaryV2"
```

### Chaos Testing
```powershell
# Start chaos test
.\Start-ServiceFabricChaos.ps1 `
    -TimeToRun 60 `
    -MaxConcurrentFaults 3 `
    -EnableMoveReplicaFaults $true
```

## REST API Patterns

### Query Applications
```powershell
$endpoint = "https://mycluster:19080/Applications?api-version=6.0"
.\Invoke-ServiceFabricRestApi.ps1 -Endpoint $endpoint -Method GET
```

### Get Node Health
```powershell
$endpoint = "https://mycluster:19080/Nodes/NodeName/$/GetHealth?api-version=6.0"
.\Invoke-ServiceFabricRestApi.ps1 -Endpoint $endpoint
```

### Start Application Upgrade
```powershell
$body = @{
    TargetApplicationTypeVersion = "2.0"
    Parameters = @{}
} | ConvertTo-Json

.\Invoke-ServiceFabricRestApi.ps1 `
    -Endpoint "https://mycluster:19080/Applications/MyApp/$/Upgrade?api-version=6.0" `
    -Method POST `
    -Body $body
```

## ETL Tracing Levels

| Level | Value | Description |
|-------|-------|-------------|
| Critical | 1 | Critical errors only |
| Error | 2 | All errors |
| Warning | 3 | Errors + warnings |
| Info | 4 | Informational messages (default) |
| Verbose | 5 | Detailed diagnostic info |

```powershell
# Start trace with specific level
.\Start-ServiceFabricEtlTracing.ps1 -TraceLevel 5 -Duration 300
```

## Troubleshooting Scenarios

### Cluster Connectivity Issues
```powershell
# Verify endpoint accessibility
Test-NetConnection -ComputerName "mycluster.eastus.cloudapp.azure.com" -Port 19000

# Test certificate authentication
.\Connect-ServiceFabricCluster.ps1 -ConnectionEndpoint "..." -X509Credential -Verbose
```

### Application Deployment Failures
```powershell
# Check image store contents
.\Get-ServiceFabricImageStore.ps1

# Verify ARM applications
.\Get-ServiceFabricArmApplications.ps1 -ResourceGroup "MyRG"
```

### Node Health Problems
```powershell
# Get quick status
.\Get-ServiceFabricQuickStatus.ps1

# Disable problematic node
.\Disable-ServiceFabricNode.ps1 -NodeName "_NodeType0_2" -Intent RemoveData
```

### Upgrade Stuck
```powershell
# Repair upgrade domain
.\Repair-ServiceFabricUpgradeDomain.ps1 -UpgradeDomain "UD3"

# Force restart with reboot
.\Start-ServiceFabricClusterUpgradeReboot.ps1 -Force
```

## Performance Considerations

### ETL Tracing
- **Trace Level**: Use level 4 (Info) for normal ops, level 5 (Verbose) only when debugging
- **File Size**: Limit to 1-2GB to prevent disk space issues
- **Auto-Rotation**: Enable automatic file rotation for long-running traces

### REST API Calls
- **Connection Pooling**: Reuse connections when making multiple calls
- **Timeout**: Set appropriate timeouts (default 30s may be too short)
- **Pagination**: Use continuation tokens for large result sets

### Docker Operations
- **Prune Regularly**: Run Clear-ServiceFabricDocker.ps1 weekly
- **Monitor Resources**: Watch disk space and container memory
- **Named Pipes**: Use for local communication when possible

## Security Best Practices

1. **Certificate Management**
   - Store certificates in secure locations (CurrentUser\My)
   - Use separate certs for dev/prod
   - Monitor expiration dates

2. **Credential Handling**
   - Never hardcode credentials or thumbprints
   - Use Azure Key Vault for secrets
   - Prefer managed identity when available

3. **Network Access**
   - Restrict management endpoint (19000) to admin IPs
   - Use TLS for all connections
   - Enable Azure AD authentication for production

4. **Audit Logging**
   - Enable diagnostic logs
   - Monitor cluster events
   - Track deployment history

## Related Documentation

- [Service Fabric Documentation](https://learn.microsoft.com/en-us/azure/service-fabric/)
- [Service Fabric REST API](https://learn.microsoft.com/en-us/rest/api/servicefabric/)
- [Service Fabric PowerShell](https://learn.microsoft.com/en-us/powershell/module/servicefabric/)
- [SFCTL Reference](https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-sfctl)
- [Managed Clusters](https://learn.microsoft.com/en-us/azure/service-fabric/overview-managed-cluster)

## Testing

```powershell
Invoke-Pester -Path ..\..\tests\powershell\*ServiceFabric*.Tests.ps1
```

## Contributing

When adding new Service Fabric scripts:
1. Follow [PowerShell Verb-Noun naming](../../docs/NAMING-CONVENTIONS.md)
2. Prefix with `ServiceFabric` (e.g., Get-ServiceFabricStatus.ps1)
3. Include comment-based help with Service Fabric-specific examples
4. Add certificate and connection parameter sets
5. Write Pester tests with mocked SF connections
6. Document REST API endpoints used
