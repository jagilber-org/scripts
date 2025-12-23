# jagilber-org/scripts

**Multi-language automation scripts, diagnostics, and utilities**

A curated collection of production-ready scripts for Azure management, Service Fabric diagnostics, data collection, and general automation. Modernized from [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts) with improved organization, comprehensive testing, and multi-language support.

---

## 🚀 Quick Start

```powershell
# Clone the repository
git clone https://github.com/jagilber-org/scripts.git
cd scripts

# Run a script (example)
.\powershell\azure\Get-AzResourceUsage.ps1 -SubscriptionId "your-sub-id"

# Run tests
Invoke-Pester .\tests\powershell\
```

---

## 📂 Structure

```
scripts/
├── powershell/         # PowerShell scripts
│   ├── azure/          # Azure management (az module)
│   ├── service-fabric/ # Service Fabric diagnostics
│   ├── diagnostics/    # General troubleshooting
│   ├── data-collection/# Log collectors, ETL processing
│   ├── automation/     # Automation workflows
│   └── utilities/      # General-purpose tools
├── python/             # Python scripts
├── bash/               # Bash scripts
├── tests/              # Comprehensive test suite
└── docs/               # Documentation & guides
```

---

## 🎯 Featured Scripts

### Azure Management
- **Get-AzResourceUsage** - Track Azure subscription resource utilization
- **Connect-AzureRESTApi** - Direct Azure REST API authentication
- **Update-AzureResource** - Patch Azure resources via ARM APIs

### Service Fabric Diagnostics
- **Backup-ServiceFabricPartition** - Automated partition backup
- **Get-ServiceFabricClusterHealth** - Health monitoring and reporting
- **Collect-ServiceFabricLogs** - Comprehensive log collection

### Data Collection
- **Collect-AzureLogs** - Azure diagnostic log harvesting
- **Export-ETLTrace** - ETL file processing and conversion
- **Gather-SystemDiagnostics** - Windows diagnostic collection

_(More scripts being migrated - see [MIGRATION-PLAN.md](MIGRATION-PLAN.md))_

---

## 📋 Standards

### Naming Convention
- **PowerShell:** `Verb-Noun-Context.ps1` (approved PowerShell verbs)
- **Python:** `snake_case.py` (PEP 8 compliant)
- **Bash:** `kebab-case.sh` (POSIX compliant)

### Testing
- **Pester tests** for all PowerShell scripts
- **pytest** for Python scripts
- **bats** for Bash scripts
- Pre-commit hooks enforce standards

### Documentation
Every script includes:
- Synopsis & description
- Parameter documentation
- Usage examples
- Original source link (if migrated)

---

## 🔗 Migration from powershellscripts

This repo is a **modernized evolution** of [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts).

**Old repo strategy:**
- Remains **unchanged** - all existing links stay valid
- Reference material preserved
- Historical context maintained

**New repo benefits:**
- ✅ Clean organization by category
- ✅ Modern naming conventions
- ✅ Comprehensive testing
- ✅ Multi-language support
- ✅ Portfolio-ready presentation
- ✅ Active maintenance

**Finding migrated scripts:**
- See [docs/LEGACY-MAPPING.md](docs/LEGACY-MAPPING.md) for old → new name mappings
- All scripts include source link in header

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick checklist:**
- Follow naming conventions
- Include Pester tests
- Update documentation
- Pass pre-commit hooks
- Link to original source if migrating

---

## 📜 License

MIT License - See [LICENSE](LICENSE)

---

## 📊 Migration Progress

**Status:** 🚧 Active Migration  
**Scripts Migrated:** 0 / TBD  
**Categories Established:** 6  
**Tests Added:** 0  

See [MIGRATION-PLAN.md](MIGRATION-PLAN.md) for detailed progress tracking.
