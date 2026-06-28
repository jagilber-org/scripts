# Category Index — Scripts by Use Case

Find the right script for your task. Scripts are grouped by common use cases across all categories.

---

## Authentication & Identity

| Script | Category | Description |
|---|---|---|
| `Connect-AzMsalAuth` | azure | MSAL-based Azure authentication |
| `Connect-AzRestApi` | azure | Direct Azure REST API authentication |
| `New-AzAadServicePrincipal` | azure | Create AAD service principals |
| `Add-AzKeyVaultToAad` | azure | Register Key Vault in AAD |
| `Connect-ServiceFabricCluster` | service-fabric | Cluster connection with multiple auth methods |
| `Connect-ServiceFabricManaged` | service-fabric | Managed cluster authentication |
| `Connect-ServiceFabricManagedAdo` | service-fabric | Managed cluster auth from Azure DevOps |
| `Invoke-GraphApi` | utilities | Microsoft Graph API calls |

## Cost Management & Billing

| Script | Category | Description |
|---|---|---|
| `Get-AzCostAnalysisReport` | azure | Comprehensive Azure cost analysis |
| `Get-AzCostTrendAnalysis` | azure | Cost trends over time |
| `Get-AzVmSkuCostReport` | azure | VM SKU cost comparison |
| `Export-AzCosts` | utilities | Export Azure cost data |

## VM & Compute Management

| Script | Category | Description |
|---|---|---|
| `Manage-AzVm` | azure | VM lifecycle management |
| `Get-AzVmImage` | azure | List available VM images |
| `Get-AzVmssImage` | azure | VMSS image management |
| `Get-AzVmSkuAnalysisReport` | azure | VM SKU analysis and recommendations |
| `Get-AzAvailableSkus` | azure | Available compute SKUs by region |
| `Find-AzImageBuild` | azure | Search for image builds |
| `Enable-AzVmRdp` | azure | Enable RDP access to VMs |
| `New-AzVmssSnapshot` | azure | VMSS disk snapshots |
| `Invoke-AzVmssCommand` | azure | Run commands on VMSS instances |
| `Add-AzVmssAppGateway` | azure | Attach Application Gateway to VMSS |

## Networking

| Script | Category | Description |
|---|---|---|
| `Add-AzNetworkSecurityRule` | azure | Manage NSG rules |
| `Enable-AzVnetFlowLog` | azure | Network traffic flow logging |
| `Manage-AzLoadBalancerRule` | azure | Load balancer rule management |
| `Watch-AzLoadBalancer` | azure | Monitor load balancer health |
| `Add-NetworkRoute` | utilities | Add network routes |
| `Start-NetworkTrace` | utilities | Network packet capture |
| `Watch-NetworkPort` | utilities | Monitor network ports |
| `Test-HttpClientPort` | utilities | Test HTTP port connectivity |
| `Test-HttpListener` | utilities | HTTP endpoint testing |
| `Test-TcpListener` | utilities | TCP port listener |
| `Test-UdpListener` | utilities | UDP port listener |

## Storage & Data

| Script | Category | Description |
|---|---|---|
| `Mount-AzFileShare` | azure | Mount Azure File Shares |
| `Publish-AzStorageFile` | azure | Upload files to Azure Storage |
| `New-AzSasToken` | azure | Generate SAS tokens |
| `Get-AzStorageTableData` | azure | Query Azure Table Storage |
| `New-AzSqlDatabase` | azure | Create SQL databases |
| `Invoke-AzSqlQuery` | azure | Run Azure SQL queries |

## Key Vault & Certificates

| Script | Category | Description |
|---|---|---|
| `Manage-AzKeyVault` | azure | Key Vault operations and secrets |
| `New-AzKeyVaultCertificate` | azure | Create Key Vault certificates |
| `Import-AzMetadataCertificate` | azure | Import metadata certificates |
| `New-TestCertificate` | utilities | Generate test certificates |
| `New-CertificateRequest` | utilities | Create certificate signing requests |
| `Convert-PfxToPem` | utilities | Convert PFX to PEM format |
| `Get-CertificateMachineKey` | utilities | Find certificate machine keys |

## Service Fabric — Cluster Operations

| Script | Category | Description |
|---|---|---|
| `Get-ServiceFabricQuickStatus` | service-fabric | Fast cluster health assessment |
| `Disable-ServiceFabricNode` | service-fabric | Disable cluster nodes |
| `Repair-ServiceFabricUpgradeDomain` | service-fabric | Fix stuck upgrade domains |
| `Restart-ServiceFabricWarningReplicas` | service-fabric | Restart unhealthy replicas |
| `Start-ServiceFabricClusterUpgradeReboot` | service-fabric | Cluster upgrade with reboot |
| `Find-ServiceFabricNodeType` | service-fabric | Search for node types |
| `Update-ServiceFabricManagedPrimary` | service-fabric | Update managed primary node type |
| `Test-ServiceFabricNodeTypeScaling` | service-fabric | Test node type scaling |

## Service Fabric — Deployment & Configuration

| Script | Category | Description |
|---|---|---|
| `Deploy-ServiceFabricManaged` | service-fabric | Deploy managed clusters |
| `Export-ServiceFabricArmTemplate` | service-fabric | Extract ARM templates |
| `Get-ServiceFabricArmApplications` | service-fabric | List ARM-deployed applications |
| `Set-ServiceFabricSettings` | service-fabric | Configure cluster settings |
| `Set-ServiceFabricImageStoreSettings` | service-fabric | Image store configuration |
| `Set-ServiceFabricManagedApim` | service-fabric | APIM integration |
| `Update-ServiceFabricStandaloneManifest` | service-fabric | Update standalone manifests |
| `Add-ServiceFabricRuntimeToImageStore` | service-fabric | Add runtime packages |
| `Install-ServiceFabricSdk` | service-fabric | Install the SF SDK |
| `New-ServiceFabricDevClusterSecure` | service-fabric | Create secure dev cluster |
| `Test-ServiceFabricManagedIdentity` | service-fabric | Test managed identity config |

## Service Fabric — Docker & Containers

| Script | Category | Description |
|---|---|---|
| `Clear-ServiceFabricDocker` | service-fabric | Clean up Docker resources |
| `Get-ServiceFabricDockerLog` | service-fabric | Retrieve Docker logs |
| `Watch-ServiceFabricDocker` | service-fabric | Monitor Docker containers |
| `Watch-ServiceFabricDockerPlugin` | service-fabric | Monitor Docker plugin |
| `Remove-ServiceFabricDockerPlugin` | service-fabric | Remove Docker plugin |
| `Connect-ServiceFabricDockerNamedPipe` | service-fabric | Docker named pipe connectivity |

## Service Fabric — Tracing & Diagnostics

| Script | Category | Description |
|---|---|---|
| `Start-ServiceFabricEtlTracing` | service-fabric | ETL trace collection |
| `Start-ServiceFabricRealtimeTracing` | service-fabric | Real-time tracing |
| `Start-ServiceFabricHnsTracing` | service-fabric | HNS network tracing |
| `Start-ServiceFabricAutoTracing` | service-fabric | Automated trace collection |
| `Start-ServiceFabricChaos` | service-fabric | Chaos testing |
| `Convert-ServiceFabricEtl` | service-fabric | Convert SF ETL files |
| `Get-ServiceFabricMetadata` | service-fabric | Cluster metadata retrieval |
| `Get-ServiceFabricCab` | service-fabric | Download SF cab packages |
| `Get-ServiceFabricImageStore` | service-fabric | Image store content |
| `Get-ServiceFabricRdpPort` | service-fabric | Find RDP ports for nodes |

## Service Fabric — REST API

| Script | Category | Description |
|---|---|---|
| `Invoke-ServiceFabricRestApi` | service-fabric | SF REST API calls |
| `Invoke-ServiceFabricRestQuery` | service-fabric | SF REST queries |
| `Invoke-ServiceFabricHttpClient` | service-fabric | SF HTTP client operations |
| `Invoke-ServiceFabricLinuxRest` | service-fabric | SF Linux REST calls |
| `Connect-ServiceFabricCtl` | service-fabric | sfctl CLI connectivity |
| `Remove-ServiceFabricApplication` | service-fabric | Remove applications via REST |

## Diagnostics & Performance

| Script | Category | Description |
|---|---|---|
| `Get-ProcessMemory` | diagnostics | Memory usage and leak detection |
| `Watch-Process` | diagnostics | Real-time process monitoring |
| `Convert-EtlFile` | diagnostics | ETL to human-readable format |
| `Show-PerfMonGraph` | diagnostics | Performance counter visualization |
| `Invoke-PerfMonAction` | diagnostics | Performance monitor automation |
| `Start-DotNetTrace` | diagnostics | .NET trace collection |
| `Start-ProcessMonitor` | diagnostics | Process Monitor automation |
| `Manage-EventLog` | diagnostics | Event log management |
| `Get-WindowsLogonDiagnostics` | diagnostics | Windows logon troubleshooting |

## Data Collection & Kusto

| Script | Category | Description |
|---|---|---|
| `Invoke-KustoQuery` | data-collection | Azure Data Explorer queries |
| `Invoke-KustoQueryV2` | data-collection | Kusto queries (v2 API) |
| `Install-KustoEmulator` | data-collection | Install Kusto emulator |
| `Merge-LogFile` | data-collection | Multi-source log aggregation |
| `Merge-PowerShellLog` | data-collection | PowerShell log merging |
| `Get-EventLogMetadata` | data-collection | Event log metadata extraction |
| `Get-CimClass` | data-collection | CIM class enumeration |
| `Get-WmiClass` | data-collection | WMI class enumeration |

## Automation & Scheduling

| Script | Category | Description |
|---|---|---|
| `Start-ParallelJob` | automation | Concurrent PowerShell execution |
| `New-ScheduledTask` | automation | Windows task scheduling |
| `Watch-HyperVVm` | automation | Monitor Hyper-V VMs |
| `Import-EnvironmentFile` | automation | Load .env files |
| `Resolve-EnvironmentPath` | automation | Resolve environment paths |
| `Publish-DualRepo` | automation | Dual-repo publishing workflow |
| `Publish-ToPublicRepo` | automation | Publish to public mirror |

## Deployment & Templates

| Script | Category | Description |
|---|---|---|
| `Deploy-AzTemplate` | azure | Deploy ARM/Bicep templates |
| `Get-AzDeploymentTemplate` | azure | Retrieve deployment templates |
| `Update-AzResource` | azure | Update Azure resources |
| `Manage-AzTag` | azure | Azure resource tagging |
| `Deploy-File` | utilities | General file deployment |
| `Deploy-RdsTemplate` | utilities | RDS deployment templates |

## Remote Desktop Services (RDS)

| Script | Category | Description |
|---|---|---|
| `Get-RdsDisconnectReason` | utilities | RDS disconnect reason codes |
| `Get-AllRdsDisconnectReasons` | utilities | All RDS disconnect reasons |
| `Get-RdsPerDeviceLicense` | utilities | RDS per-device license info |
| `Get-RdsVdiInfo` | utilities | RDS VDI information |
| `Manage-RdsUserProfile` | utilities | RDS user profile management |
| `Remove-RdsLicenseByClient` | utilities | Remove RDS licenses by client |
| `Remove-RdsLicenseByDate` | utilities | Remove RDS licenses by date |
| `Test-RdsLicenseServer` | utilities | Test RDS license server |
| `Deploy-RdsTemplate` | utilities | RDS deployment templates |

## File & Text Operations

| Script | Category | Description |
|---|---|---|
| `Search-FileContent` | utilities | Fast file content search with regex |
| `Compare-Directory` | utilities | Directory comparison |
| `Compare-FileContent` | utilities | File content diff |
| `Copy-FileWithProgress` | utilities | File copy with progress bar |
| `Split-File` | utilities | Split large files |
| `Get-DirectorySize` | utilities | Directory size analysis |
| `Get-UniqueLines` | utilities | Extract unique lines from files |
| `New-TextFilter` | utilities | Text filtering utility |
| `Remove-ByteOrderMark` | utilities | Remove BOM from files |
| `Convert-StringEncoding` | utilities | String encoding conversion |
| `Convert-JsonTick` | utilities | JSON tick timestamp conversion |
| `Add-SourceUri` | utilities | Add source URI to scripts |

## Development Tools

| Script | Category | Description |
|---|---|---|
| `Install-GitClient` | utilities | Install Git client |
| `Install-GitVsCode` | utilities | Install Git + VS Code |
| `Install-SysinternalsTool` | utilities | Install Sysinternals tools |
| `Install-ServerOsWinget` | utilities | Install winget on Server OS |
| `Install-Mirantis` | utilities | Install Mirantis container runtime |
| `Install-PreCommitHook` | utilities | Setup pre-commit hooks |
| `Start-DeveloperPrompt` | utilities | Developer command prompt |
| `Set-CustomPrompt` | utilities | Custom PowerShell prompt |
| `New-ScriptTemplate` | utilities | Generate script template |
| `Get-GitRelease` | utilities | Download GitHub releases |
| `Invoke-NuGetCommand` | utilities | NuGet package operations |
| `Invoke-OpenAI` | utilities | OpenAI API integration |
| `New-GuidBatch` | utilities | Generate batches of GUIDs |
| `Get-TimeDifference` | utilities | Calculate time differences |
| `Update-MarkdownImage` | utilities | Update image refs in markdown |

## System Administration

| Script | Category | Description |
|---|---|---|
| `Get-RegistryPermission` | utilities | Registry permission audit |
| `Set-RegistryPermission` | utilities | Set registry permissions |
| `Set-DesktopHeap` | utilities | Configure desktop heap size |
| `Enable-FileAuditing` | utilities | Enable file system auditing |
| `Register-EventTask` | utilities | Register event-based tasks |
| `Get-TerminalSession` | utilities | Terminal session info |
| `Invoke-UmdhAnalysis` | utilities | User-mode dump heap analysis |
| `Start-UmdhTask` | utilities | Schedule UMDH collection |
| `Test-PreCommitHook` | utilities | Validate pre-commit hooks |
| `Set-VmssCseTls` | utilities | Configure TLS on VMSS CSE |

## Azure DevOps & CI/CD

| Script | Category | Description |
|---|---|---|
| `Invoke-AzDevOpsApi` | azure | Azure DevOps REST API calls |
| `Invoke-AzMetadataApi` | azure | Azure metadata API |
| `Invoke-AzRestQuery` | azure | Generic Azure REST queries |
| `Get-AzModuleCommand` | utilities | Search Az module commands |

---

*169 PowerShell scripts | 4 C# scripts | 2 Azure DevOps YAML | 1 Shell script*
