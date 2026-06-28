# jagilber-org/scripts

[![Run Tests](https://github.com/jagilber-org/scripts/actions/workflows/test.yml/badge.svg)](https://github.com/jagilber-org/scripts/actions/workflows/test.yml) [![Lint](https://github.com/jagilber-org/scripts/actions/workflows/lint.yml/badge.svg)](https://github.com/jagilber-org/scripts/actions/workflows/lint.yml)

**Production-ready automation scripts for Azure, Service Fabric, and DevOps**

A comprehensive collection of 176 scripts (169 PowerShell, 4 C#, 2 Azure DevOps, 1 Shell) for Azure resource management, Service Fabric cluster operations, diagnostics, data collection, and automation. Modernized from [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts) with improved organization, comprehensive testing, and CI/CD automation.

---

## � Security Notice

This repository follows [GitHub Spec-Kit](https://github.com/ambie-inc) security standards:

- **Pre-commit hooks**: Prevents accidental commit of credentials and PII
- **Environment variables**: Use `.env.example` as template, never commit actual `.env`
- **Config files**: `*.example.json` files are templates; actual config files are gitignored
- **Placeholder data**: All examples use generic values (John Doe, user@example.com, your-sub-id)

**For contributors**: Review security guidelines in the Contributing section before making changes.

---

## 🚀 Quick Start

### First-Time Setup

```powershell
# Clone the repository
git clone https://github.com/jagilber-org/scripts.git
cd scripts

# Browse scripts by category
Get-ChildItem powershell\azure
Get-ChildItem powershell\service-fabric
Get-ChildItem csharp
Get-ChildItem ado

# Run a script (example with placeholder values)
.\powershell\azure\Get-AzLog.ps1 -SubscriptionId "your-subscription-id-here"

# Run all tests
.\Run-Tests.ps1
```

---

## 📂 Repository Structure

```
scripts/
├── powershell/              # PowerShell scripts (169 total)
│   ├── azure/              # Azure management (40 scripts)
│   ├── service-fabric/     # Service Fabric operations (44 scripts)
│   ├── diagnostics/        # Troubleshooting tools (9 scripts)
│   ├── data-collection/    # Log collectors, ETL processing (8 scripts)
│   ├── automation/         # Workflow automation (7 scripts)
│   └── utilities/          # General-purpose tools (61 scripts)
├── csharp/                  # C# scripts (4 total)
├── shell/                   # Shell scripts (1 total)
├── ado/                     # Azure DevOps YAML (2 total)
├── tests/powershell/        # Pester test suite (176 test files)
├── docs/                    # Documentation & guides
└── .github/workflows/       # CI/CD automation
```

---

## 🎯 Script Categories

### PowerShell Scripts (169)

#### Azure Management (40 scripts)
Resource management, networking, storage, authentication, cost analysis, and monitoring for Azure services using Az PowerShell module.

**Featured:**
- `Get-AzCostAnalysisReport` - Comprehensive Azure cost analysis
- `Connect-AzRestApi` - Direct Azure REST API authentication
- `Manage-AzKeyVault` - Key Vault operations and secrets management
- `Enable-AzVnetFlowLog` - Network traffic flow logging

#### Service Fabric (44 scripts)
Cluster management, diagnostics, Docker operations, tracing, and managed cluster support for Azure Service Fabric.

**Featured:**
- `Connect-ServiceFabricCluster` - Cluster connection with multiple auth methods
- `Get-ServiceFabricQuickStatus` - Fast cluster health assessment
- `Export-ServiceFabricArmTemplate` - ARM template extraction
- `Start-ServiceFabricEtlTracing` - ETL trace collection

#### Diagnostics (9 scripts)
System troubleshooting, performance monitoring, event log analysis, and process diagnostics.

**Featured:**
- `Get-ProcessMemory` - Memory usage analysis and leak detection
- `Convert-EtlFile` - ETL to human-readable format conversion
- `Watch-Process` - Real-time process monitoring

#### Data Collection (8 scripts)
Kusto queries, log aggregation, WMI/CIM enumeration, and data processing utilities.

**Featured:**
- `Invoke-KustoQuery` - Azure Data Explorer query execution
- `Merge-LogFile` - Multi-source log file aggregation

#### Automation (7 scripts)
Scheduled tasks, parallel job execution, environment configuration management, and dual-repo publishing.

**Featured:**
- `Start-ParallelJob` - Concurrent PowerShell job execution
- `New-ScheduledTask` - Automated task scheduling
- `Publish-DualRepo` - Dual-repo publishing workflow

#### Utilities (61 scripts)
Certificates, networking, development tools, RDS management, and general-purpose utilities.

**Featured:**
- `New-TestCertificate` - Test certificate generation
- `Search-FileContent` - Fast file content search with regex
- `Test-HttpListener` - HTTP endpoint testing

### C# Scripts (4)

Interactive C# scripts (.csx) for advanced Azure operations and system tasks using the C# scripting API.

**Featured:**
- `NetUserGetLocalGroups.csx` - Windows local group enumeration
- `cosmos-test.csx` - Azure Cosmos DB testing
- `keyvault-test.csx` - Azure Key Vault operations
- `multithread-file-split.csx` - Parallel file processing

### Shell Scripts (1)

Bash/shell scripts for cross-platform automation.

**Featured:**
- `autoscale-formula-cpupercent.sh` - Azure Batch autoscale formula

### Azure DevOps (2)

YAML pipeline tasks for Azure DevOps automation.

**Featured:**
- `azure-devops-artifacts-storage-task.yml` - Artifact storage management
- `azure-devops-powershell-troubleshooting-task.yml` - PowerShell diagnostics

---

## 📋 Quality Standards

### Spec-Kit Governance
This repository uses [GitHub Spec-Kit](https://github.com/ambie-inc) methodology for governance:
- **Constitution**: Machine-checkable rules in `constitution.json` covering quality, security, architecture, governance, and testing
- **Sync check**: Run `.\sync-constitution.ps1 -Check` to verify `constitution.md` is in sync (enforced in CI)
- **Dual-repo model**: `jagilber-dev/scripts` is the canonical development source; `jagilber-org/scripts` is the public mirror published via `scripts/Publish-ToPublicRepo.ps1`

### Naming Convention
All PowerShell scripts follow approved verb-noun naming:
- **Format:** `Verb-Noun.ps1`
- **Verbs:** Get, Set, New, Remove, Connect, Start, etc.
- **Examples:** `Get-AzLog.ps1`, `Connect-ServiceFabricCluster.ps1`

### Testing
- ✅ 100% test coverage for PowerShell (176 Pester test files)
- ✅ Automated testing via GitHub Actions
- ✅ Code quality checks with PSScriptAnalyzer
- ✅ Constitution sync check in CI
- Run tests: `.\Run-Tests.ps1`

### Documentation
Every script includes:
- ✅ Synopsis & detailed description
- ✅ Parameter documentation with types
- ✅ Usage examples
- ✅ Author and version information

### CI/CD
- ✅ Automated tests on every push/PR
- ✅ Code quality linting
- ✅ Automated release creation with changelogs

---

## 🔗 Migration from powershellscripts

This repository is a modernized version of [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts).

**What changed:**
- ✅ Organized into 6 PowerShell categories + 3 language-specific folders
- ✅ All PowerShell scripts renamed to conventions
- ✅ Comprehensive Pester test suite added
- ✅ Category documentation with usage guides
- ✅ GitHub Actions CI/CD workflows
- ✅ Portfolio-ready presentation

**Original repository:**
- Remains unchanged and accessible
- All existing links continue to work
- Historical reference preserved

---

## 🤝 Contributing

Contributions welcome! Please follow these guidelines:

### Code Standards
- Follow PowerShell verb-noun naming conventions for .ps1 scripts
- Include Pester tests for new PowerShell scripts
- Update category README if adding new scripts
- Ensure all tests pass: `.\Run-Tests.ps1`

### Repository Ownership Policy
This repository follows strict contribution guidelines per [GitHub Spec-Kit](https://github.com/ambie-inc) standards:

- **No automatic PRs**: Contributors must have explicit permission before creating pull requests
- **Manual review required**: All contributions undergo code review and security checks
- **Testing mandatory**: New scripts must include comprehensive Pester tests
- **Documentation required**: Update relevant README files with examples

### Documentation Standards
**IMPORTANT**: Follow these documentation practices:

- ✅ **Use placeholder values** in all examples:
  - Subscription IDs: `your-subscription-id-here`
  - Email addresses: `user@example.com`, `admin@contoso.com`
  - Names: John Doe, Jane Smith, Example Corp
  - Resource groups: `my-resource-group`, `example-rg`
  - Storage accounts: `mystorageaccount`, `examplestorage`

- ❌ **Never include**:
  - Real credentials, API keys, or secrets
  - Actual email addresses or subscription IDs
  - Personal information or company-specific data
  - Production resource names or identifiers

- ✅ **Do document**:
  - Parameter types and descriptions
  - Usage examples with placeholders
  - Error handling and troubleshooting
  - Prerequisites and dependencies

---

## 📜 License

MIT License - See [LICENSE](LICENSE)

---

## 📊 Repository Statistics

- **Total Scripts:** 174
  - PowerShell: 167
  - C#: 4
  - Shell: 1
  - Azure DevOps: 2
- **Categories:** 9 (6 PowerShell + 3 language-specific)
- **Test Coverage:** 100% for PowerShell (167 test files)
- **Documentation:** 6 category READMEs + comprehensive guides
- **CI/CD:** Automated testing, linting, and releases
- **Migration:** Complete ✅
