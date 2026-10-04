# Changelog

## [Unreleased]

### Added

- `Export-PerfCounterHelp.ps1`: dump performance counter descriptions (the PerfMon "Show description" text) through PDH, with counter-type decoding and a `-BlgPath` filter for counters in a log, since PerfMon cannot show descriptions for BLG data sources
- Squad adoption from `jagilber-dev/squad-template-repo` with functional agent names (Architect, Sentinel, Adopter, Scout, Scribe)
- Copilot MCP config and 8 skill definitions (agent-collaboration, error-recovery, git-workflow, etc.)
- `powershell/automation/Update-OrgProfileReadme.ps1` - generates a GitHub org profile
  README from live repository metadata. Org-specific text and grouping come from an
  optional JSON config kept outside this repo, so the script is reusable for any org.
  Summaries prefer the GitHub description and fall back to the README; quick-start
  blocks are copied only from real Install/Usage sections and never inferred from the
  repo name; absolute local paths and secret-shaped tokens are stripped. Covered by 50
  offline Pester tests. (This entry previously listed the script while no such file was
  present in the tree - it was lost in the 2026-08 history rewrite.)
- Test fixtures for Service Fabric ARM template export testing
- `.gitattributes` with union merge strategy for squad state files

### Changed

- `Invoke-BoundedPerfMonCollection.ps1`: kept the resilient local-only Windows PowerShell 5.1 lifecycle and expanded the fixed set from 35 to 50 counters for page faults, disk IOPS/current queue, absolute free space, network capacity/errors/discards, TCP retransmits, and process fault/other-I/O attribution
- `Export-ServiceFabricArmTemplate.ps1`: enhanced parameter handling and refactored
- `Publish-ToPublicRepo.ps1`: added try/finally cleanup, robocopy error handling, removed hardcoded local path
- `Export-AzCostReport.ps1`: fixed param-time evaluation bug, removed dead code branch

### Fixed

- `Import-CentralEnv.ps1`: replaced breaking mandatory `$Path` with deprecation warning and legacy default
- `Compare-AzProcessMemory.ps1`: fixed empty-array crash in `Get-StatObject` with proper null/count guard
- `Sync-VSCodeExtensionsToInsiders.ps1`: corrected `.EXAMPLES` to `.EXAMPLE` for Get-Help compatibility
