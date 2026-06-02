# PowerShellScripts → jagilber-org/scripts Migration Plan

**Goal:** Modernize script collection with clean structure, multi-language support, comprehensive testing, and portfolio-ready presentation.

**Source:** [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts) (preserved as-is, links remain valid)  
**Target:** jagilber-org/scripts (fresh start, curated, organized)

---

## Phase 1: Foundation & Bulk Copy ✅ COMPLETE

### 1.1 Repository Setup
- [x] Create jagilber-org/scripts repo
- [x] Setup .gitignore (PowerShell, Python, Bash, logs, secrets)
- [x] Add LICENSE (MIT)
- [x] Configure pre-commit hooks (detect-secrets, trailing-whitespace, Pester tests)
- [x] Add .secrets.baseline

### 1.2 Folder Structure
- [x] Created 6 PowerShell category folders (azure, service-fabric, diagnostics, data-collection, automation, utilities)
- [x] Created tests/powershell/ for Pester tests
- [x] Created docs/ with NAMING-CONVENTIONS.md and TESTING-GUIDE.md
- [x] Created .github/workflows/ with test.yml, lint.yml, release.yml
- [x] Added csharp/, shell/, ado/ for non-PowerShell content

### 1.3 Bulk Copy & Categorization
- [x] Copied and categorized all scripts directly into category folders (no _unsorted/ needed)
- [x] Renamed scripts to Verb-Noun PascalCase convention
- [x] Added header comments with source links

---

## Phase 2: Standards & Conventions ✅ COMPLETE

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

## Phase 3: Categorization & Migration ✅ COMPLETE

All 169 PowerShell scripts categorized across 6 folders with Verb-Noun naming applied.

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

## Phase 4: Pruning & Quality ✅ COMPLETE

No unsorted or deprecated scripts remain. All scripts are categorized and functional.

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

## Phase 5: Documentation & CI ✅ COMPLETE

### 5.1 Documentation
- [x] README with featured scripts
- [x] Category index (use cases → scripts) — `docs/CATEGORY-INDEX.md`
- [x] Legacy mapping for old links — `docs/LEGACY-MAPPING.md`
- [x] Testing guide for contributors — `docs/TESTING-GUIDE.md`
- [x] Naming conventions guide — `docs/NAMING-CONVENTIONS.md`

### 5.2 CI/CD
- [x] GitHub Actions for Pester tests (`.github/workflows/test.yml`)
- [x] Pre-commit hooks enforcement (`.pre-commit-config.yaml`)
- [x] PSScriptAnalyzer integration (`.github/workflows/lint.yml`)
- [x] Automated releases (`.github/workflows/release.yml`)
- [ ] Code coverage reporting (test results uploaded, coverage threshold TBD)

---

## Progress Tracking

**Total PowerShell Scripts:** 169  
**Categorized:** 169 (100%)  
**Test Files:** 176 (100%+ coverage — includes infra tests)  
**Deprecated:** 0 (all scripts active)  

| Category | Scripts |
|---|---|
| Azure | 40 |
| Service Fabric | 44 |
| Diagnostics | 9 |
| Data Collection | 8 |
| Automation | 7 |
| Utilities | 61 |

**Non-PowerShell:** 4 C# scripts, 2 Azure DevOps YAML, 1 Shell script

### Remaining Items
- [ ] Code coverage threshold configuration
- [ ] python/ and bash/ directories (deferred — add when content exists)

---

## Links & References

**Original Repo:** https://github.com/jagilber/powershellscripts  
**Original Repo Strategy:** Keep as-is, all links remain valid  
**Migration Tracking:** This file + LEGACY-MAPPING.md  
**Git SpecKit Compliance:** Pre-commit hooks, conventional commits, semantic versioning
