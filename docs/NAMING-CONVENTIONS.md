# PowerShell Script Naming Conventions

## Overview

This document defines the naming standards for PowerShell scripts in this repository. The goal is to provide consistent, discoverable, and PowerShell-idiomatic naming.

## General Principles

1. **PowerShell Verb-Noun Format**: Use approved PowerShell verbs followed by descriptive nouns
2. **PascalCase**: Capitalize the first letter of each word (e.g., `Get-AzureVmImages.ps1`)
3. **Descriptive**: Names should clearly indicate the script's purpose
4. **No Redundant Prefixes**: Folder structure provides context (azure/, diagnostics/, etc.)

## Approved PowerShell Verbs

Use standard PowerShell verbs from `Get-Verb`:
- **Get**: Retrieve information or resources
- **Set**: Establish or change a configuration
- **New**: Create a new resource
- **Remove**: Delete a resource
- **Add**: Add to a collection
- **Update**: Modify an existing resource
- **Test**: Validate or check conditions
- **Enable/Disable**: Turn features on/off
- **Start/Stop**: Begin or end processes
- **Deploy**: Deploy resources or templates
- **Invoke**: Execute an action
- **Export/Import**: Save or load data

## Category-Specific Guidelines

### Azure Scripts (`powershell/azure/`)

**OLD (deprecated)**: `azure-az-create-keyvault-certificate.ps1`  
**NEW**: `New-AzKeyVaultCertificate.ps1`

- Remove `azure-az-` prefix (folder provides Azure context)
- Use official Azure resource type naming (Az prefix)
- Follow Azure PowerShell cmdlet naming patterns

**Examples:**
- `azure-az-deploy-template.ps1` → `Deploy-AzTemplate.ps1`
- `azure-az-vmss-snapshot.ps1` → `New-AzVmssSnapshot.ps1`
- `azure-az-keyvault-manager.ps1` → `Manage-AzKeyVault.ps1`
- `azure-az-rest-query.ps1` → `Invoke-AzRestQuery.ps1`

### Diagnostics Scripts (`powershell/diagnostics/`)

**Pattern**: `{Verb}-{DiagnosticArea}.ps1`

**Examples:**
- `event-log-manager.ps1` → `Manage-EventLog.ps1`
- `perfmon-console-graph.ps1` → `Show-PerfMonGraph.ps1`
- `dotnet-trace-collect.ps1` → `Start-DotNetTrace.ps1`
- `process-monitor.ps1` → `Watch-Process.ps1`

### Data Collection Scripts (`powershell/data-collection/`)

**Pattern**: `{Verb}-{DataSource}.ps1`

**Examples:**
- `kusto-rest.ps1` → `Invoke-KustoQuery.ps1`
- `log-merge.ps1` → `Merge-LogFiles.ps1`
- `enum-wmi.ps1` → `Get-WmiClasses.ps1`

### Automation Scripts (`powershell/automation/`)

**Pattern**: `{Verb}-{AutomationTask}.ps1`

**Examples:**
- `schedule-task.ps1` → `New-ScheduledTask.ps1`
- `multi-job-proto.ps1` → `Start-ParallelJobs.ps1`
- `hyperv-vm-monitor.ps1` → `Watch-HyperVVm.ps1`

### Utilities Scripts (`powershell/utilities/`)

**Pattern**: `{Verb}-{Utility}.ps1`

**Examples:**
- `file-copy.ps1` → `Copy-FileWithProgress.ps1`
- `directory-compare.ps1` → `Compare-Directory.ps1`
- `convert-string.ps1` → `Convert-StringEncoding.ps1`
- `test-http-listener.ps1` → `Test-HttpListener.ps1`

## Legacy Naming Patterns to Replace

### Remove Module Distinction
- ❌ `azure-azurerm-*` (obsolete - AzureRM deprecated)
- ❌ `azure-az-*` (redundant - folder provides context)
- ✅ Use Azure resource type naming directly

### Remove Hyphenated Prefixes
- ❌ `ps-grep.ps1` → ✅ `Search-FileContent.ps1`
- ❌ `ps-net-trace.ps1` → ✅ `Start-NetworkTrace.ps1`
- ❌ `netsh-port-mon.ps1` → ✅ `Watch-NetworkPort.ps1`

### Standardize Test Scripts
- ❌ `test-http-listener.ps1` → ✅ `Test-HttpListener.ps1`
- Keep `Test-` prefix for validation scripts

## Special Cases

### Manager Scripts
Scripts with "manager" in the name should use specific verbs:
- `azure-az-keyvault-manager.ps1` → `Manage-AzKeyVault.ps1` (if multi-function)
- Or split into: `Get-AzKeyVault.ps1`, `New-AzKeyVault.ps1`, `Remove-AzKeyVault.ps1`

### RDS Scripts
Remote Desktop Services scripts retain RDS prefix for clarity:
- `rds-lic-svr-chk.ps1` → `Test-RdsLicenseServer.ps1`
- `rds-upd-mgr.ps1` → `Manage-RdsUserProfile.ps1`

### Certificate Scripts
- `certificate-machinekeys-mapper.ps1` → `Get-CertificateMachineKeys.ps1`
- `create-test-certificates.ps1` → `New-TestCertificate.ps1`

## Migration Strategy

1. **Preserve Git History**: Use `git mv` for renames to maintain history
2. **Update References**: Update any internal script references after renaming
3. **Document Changes**: Commit messages should note old → new name
4. **Batch by Category**: Rename one folder at a time

## Validation

After renaming:
- Run `Get-Verb` to ensure verbs are approved
- Check for naming conflicts within categories
- Update README files in each category
- Update test scripts to reference new names

## References

- [PowerShell Approved Verbs](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
- [PowerShell Naming Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-development-guidelines)
