# Legacy Mapping — Old → New Script Names

Maps script names from [jagilber/powershellscripts](https://github.com/jagilber/powershellscripts) to their new locations in this repository.

> **Note:** The original repository is preserved as-is. All existing links continue to work.  
> This file helps users find scripts that were renamed during migration.

---

## Naming Pattern Changes

| Old Pattern | New Pattern | Example |
|---|---|---|
| `azure-rm-*` | `*-Az*.ps1` | `azure-rm-rest-logon.ps1` → `Connect-AzRestApi.ps1` |
| `azure-az-*` | `*-Az*.ps1` | `azure-az-patch-resource.ps1` → `Update-AzResource.ps1` |
| `serviceFabric-*` | `*-ServiceFabric*.ps1` | Verb-Noun PascalCase |
| `temp-*`, `test-*` prefixes | Verb-Noun naming | Removed ad-hoc prefixes |
| kebab-case / camelCase | PascalCase Verb-Noun | Standard PowerShell conventions |

## Category Mapping

Scripts from the flat original repo were organized into categories:

| New Category | Path | Script Count |
|---|---|---|
| Azure Management | `powershell/azure/` | 40 |
| Service Fabric | `powershell/service-fabric/` | 44 |
| Diagnostics | `powershell/diagnostics/` | 9 |
| Data Collection | `powershell/data-collection/` | 8 |
| Automation | `powershell/automation/` | 7 |
| Utilities | `powershell/utilities/` | 61 |

## How to Find a Script

1. **By use case:** See [CATEGORY-INDEX.md](CATEGORY-INDEX.md) for scripts grouped by task
2. **By name:** Search with `Get-ChildItem powershell -Recurse -Filter *keyword*`
3. **By old name:** Check the script's `.NOTES` section for the `Source:` link back to the original repo

---

*For the complete script listing by category, see [CATEGORY-INDEX.md](CATEGORY-INDEX.md).*
