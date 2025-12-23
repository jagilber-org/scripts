# PowerShellScripts → jagilber-org/scripts Migration Plan

**Goal:** Modernize script collection with clean structure, multi-language support, comprehensive testing, and portfolio-ready presentation.

**Source:** [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts) (preserved as-is, links remain valid)  
**Target:** jagilber-org/scripts (fresh start, curated, organized)

---

## Phase 1: Foundation & Bulk Copy ✅ IN PROGRESS

### 1.1 Repository Setup
- [x] Create jagilber-org/scripts repo
- [ ] Setup .gitignore (PowerShell, Python, Bash, logs, secrets)
- [ ] Add LICENSE (MIT)
- [ ] Configure pre-commit hooks (detect-secrets, trailing-whitespace, Pester tests)
- [ ] Add .secrets.baseline

### 1.2 Folder Structure
```
scripts/
├── powershell/
│   ├── azure/              # Azure management (az module)
│   ├── service-fabric/     # SF diagnostics & operations
│   ├── diagnostics/        # General troubleshooting
│   ├── data-collection/    # Log collectors, ETL processing
│   ├── automation/         # Automation workflows
│   └── utilities/          # General-purpose tools
├── python/
│   ├── data-processing/
│   ├── automation/
│   └── utilities/
├── bash/
│   └── linux-tools/
├── tests/
│   ├── powershell/         # Pester tests mirror structure
│   └── integration/        # Cross-script tests
├── docs/
│   ├── NAMING-CONVENTIONS.md
│   ├── TESTING-GUIDE.md
│   ├── CATEGORY-INDEX.md   # Scripts by use case
│   └── LEGACY-MAPPING.md   # Old → New name mappings
├── .github/
│   └── workflows/
│       ├── test-powershell.yml
│       └── pre-commit.yml
└── README.md
```

### 1.3 Bulk Copy
- [ ] Copy ALL scripts from powershellscripts to `powershell/_unsorted/`
- [ ] Preserve original filenames (will rename during categorization)
- [ ] Add header comment linking back to original repo

---

## Phase 2: Standards & Conventions

### 2.1 Naming Convention (No More azurerm/az split)
**Format:** `{Verb}-{Noun}-{Context}.ps1`

**Examples:**
- `azure-rm-rest-logon.ps1` → `Connect-AzureRESTApi.ps1`
- `azure-az-patch-resource.ps1` → `Update-AzureResource.ps1`
- `serviceFabric-backup-partition.ps1` → `Backup-ServiceFabricPartition.ps1`

**Verb Standards:**
- PowerShell: Use approved verbs (`Get-Verb`)
- Python: PEP8 snake_case (`collect_azure_logs.py`)
- Bash: kebab-case (`backup-config.sh`)

### 2.2 Script Header Template
```powershell
<#
.SYNOPSIS
    Brief description
.DESCRIPTION
    Detailed explanation
.PARAMETER ParamName
    Parameter description
.EXAMPLE
    Usage example
.NOTES
    Author: jagilber
    Source: https://github.com/jagilber/powershellscripts/blob/master/original-name.ps1
    Migrated: 2025-12-23
.LINK
    https://github.com/jagilber-org/scripts
#>
```

### 2.3 Testing Requirements
- **Pester test** for each script in `tests/powershell/{category}/`
- Minimum tests:
  - Parameters validate correctly
  - Help documentation exists
  - No syntax errors
  - Core function executes (mocked external calls)

---

## Phase 3: Categorization & Migration

**Process per script:**
1. Read script, understand purpose
2. Assign category (azure, service-fabric, diagnostics, etc.)
3. Rename following convention
4. Add/update header with source link
5. Move to category folder
6. Create basic Pester test
7. Update LEGACY-MAPPING.md

**Priority Order:**
1. **Azure Management** (high value, frequently referenced)
2. **Service Fabric Diagnostics** (specialized, customer-facing)
3. **Data Collection Tools** (log collectors, ETL)
4. **Automation Scripts** (workflows, batch operations)
5. **Utilities** (general tools)
6. **Legacy/Deprecated** (azurerm only, document but low priority)

---

## Phase 4: Pruning & Quality

### 4.1 Deprecation Criteria
- **Remove:** AzureRM-only scripts with no az equivalent
- **Archive:** One-off repros with no general applicability (move to `archive/` with README)
- **Keep:** Customer issue solutions (document origin in header)
- **Keep:** Examples/demos (valuable for documentation)

### 4.2 Modernization
- Update deprecated cmdlets
- Add error handling where missing
- Standardize parameter names
- Add pipeline support where appropriate

---

## Phase 5: Documentation & CI

### 5.1 Documentation
- [ ] README with featured scripts
- [ ] Category index (use cases → scripts)
- [ ] Migration guide for old links
- [ ] Testing guide for contributors

### 5.2 CI/CD
- [ ] GitHub Actions for Pester tests
- [ ] Pre-commit hooks enforcement
- [ ] PSScriptAnalyzer integration
- [ ] Code coverage reporting

---

## Progress Tracking

**Total Scripts:** TBD (count from powershellscripts)  
**Migrated:** 0  
**Categorized:** 0  
**Tested:** 0  
**Deprecated:** 0  

### Current Sprint
- [ ] Setup Phase 1.1-1.2 (foundation)
- [ ] Bulk copy Phase 1.3
- [ ] Define 10 priority scripts for Phase 3

---

## Links & References

**Original Repo:** https://github.com/jagilber/powershellscripts  
**Original Repo Strategy:** Keep as-is, all links remain valid  
**Migration Tracking:** This file + LEGACY-MAPPING.md  
**Git SpecKit Compliance:** Pre-commit hooks, conventional commits, semantic versioning
