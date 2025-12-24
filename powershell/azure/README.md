# Azure PowerShell Scripts

This directory contains 36 PowerShell scripts for managing Azure resources, deployments, and services.

## Categories

### Resource Management
- **Manage-AzKeyVault.ps1** - Comprehensive Key Vault management (create, delete, secrets, certificates)
- **Manage-AzTag.ps1** - Tag management across resources and resource groups
- **Manage-AzVm.ps1** - Virtual machine lifecycle management
- **Manage-AzLoadBalancerRule.ps1** - Load balancer rule configuration
- **Update-AzResource.ps1** - Generic resource patching and updates

### Virtual Machines & Scale Sets
- **Get-AzVmImage.ps1** - Query available VM images by publisher, offer, SKU
- **Get-AzVmssImage.ps1** - Query VMSS image versions
- **Get-AzAvailableSkus.ps1** - List available VM SKUs by region
- **Find-AzImageBuild.ps1** - Match and find specific image builds
- **Invoke-AzVmssCommand.ps1** - Execute commands on VMSS instances
- **New-AzVmssSnapshot.ps1** - Create VMSS snapshots
- **Add-AzVmssAppGateway.ps1** - Integrate VMSS with Application Gateway
- **Enable-AzVmRdp.ps1** - Configure RDP access post-deployment

### Networking
- **Add-AzNetworkSecurityRule.ps1** - Add NSG rules
- **Enable-AzVnetFlowLog.ps1** - Configure VNet flow logging
- **Watch-AzLoadBalancer.ps1** - Monitor load balancer health and metrics

### Storage
- **Mount-AzFileShare.ps1** - Map Azure File Share as network drive
- **Get-AzStorageTableData.ps1** - Query Azure Table Storage
- **Publish-AzStorageFile.ps1** - Upload files to Azure Storage
- **New-AzSasToken.ps1** - Generate SAS tokens for storage access

### Authentication & Identity
- **Connect-AzRestApi.ps1** - Authenticate to Azure REST API
- **Connect-AzMsalAuth.ps1** - MSAL-based authentication
- **New-AzAadServicePrincipal.ps1** - Create AAD service principals
- **Add-AzKeyVaultToAad.ps1** - Configure Key Vault with AAD
- **Import-AzMetadataCertificate.ps1** - Import certificates via metadata service
- **New-AzKeyVaultCertificate.ps1** - Generate Key Vault certificates

### Deployment & Templates
- **Deploy-AzTemplate.ps1** - Deploy ARM templates
- **Get-AzDeploymentTemplate.ps1** - Download deployment templates for analysis

### APIs & DevOps
- **Invoke-AzRestQuery.ps1** - Generic Azure REST API queries
- **Invoke-AzDevOpsApi.ps1** - Azure DevOps REST API integration
- **Invoke-AzMetadataApi.ps1** - Query Azure Instance Metadata Service
- **Invoke-AzSqlQuery.ps1** - Execute queries against Azure SQL

### Monitoring & Logging
- **Get-AzLog.ps1** - Retrieve Azure activity logs
- **Watch-AzLoadBalancer.ps1** - Real-time load balancer monitoring

### Database
- **New-AzSqlDatabase.ps1** - Create and configure Azure SQL databases

### Testing
- **Test-AzLoadBalancerRuleManager.ps1** - Validate load balancer rule configurations
- **Test-AzTagManager.ps1** - Comprehensive tag manager tests

## Authentication Requirements

Most scripts require Azure authentication. Common methods:

### Interactive Login
```powershell
Connect-AzAccount
```

### Service Principal
```powershell
$credential = Get-Credential
Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId
```

### Managed Identity
```powershell
Connect-AzAccount -Identity
```

## Common Usage Patterns

### Query VM Images
```powershell
.\Get-AzVmImage.ps1 -Location "eastus" -Publisher "MicrosoftWindowsServer"
```

### Manage Tags
```powershell
.\Manage-AzTag.ps1 -ResourceGroupName "myRG" -Tags @{Environment="Production"; Owner="TeamA"}
```

### Create Key Vault
```powershell
.\Manage-AzKeyVault.ps1 -VaultName "myVault" -ResourceGroupName "myRG" -Location "eastus"
```

### Deploy ARM Template
```powershell
.\Deploy-AzTemplate.ps1 -TemplateFile ".\template.json" -ResourceGroupName "myRG"
```

## Prerequisites

- **Azure PowerShell Module**: `Install-Module -Name Az -AllowClobber`
- **Minimum Version**: Az 10.0.0 or later
- **Permissions**: Appropriate RBAC roles for target resources

## Best Practices

1. **Use -WhatIf**: Test changes before applying
2. **Parameterize**: Use parameter files for templates
3. **Tag Resources**: Always tag for cost tracking and governance
4. **Error Handling**: Scripts include try/catch blocks
5. **Logging**: Enable verbose output with -Verbose

## Related Documentation

- [Azure PowerShell Documentation](https://learn.microsoft.com/en-us/powershell/azure/)
- [ARM Template Reference](https://learn.microsoft.com/en-us/azure/templates/)
- [Azure CLI vs PowerShell](https://learn.microsoft.com/en-us/azure/developer/azure-cli/choose-the-right-azure-command-line-tool)

## Testing

Run tests for this category:
```powershell
Invoke-Pester -Path ..\..\tests\powershell\*Az*.Tests.ps1
```
