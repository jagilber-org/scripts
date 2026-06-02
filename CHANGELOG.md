# Changelog

## [Unreleased]

### Added
- Squad adoption from `jagilber-dev/squad-template-repo` with functional agent names (Architect, Sentinel, Adopter, Scout, Scribe)
- Copilot MCP config and 8 skill definitions (agent-collaboration, error-recovery, git-workflow, etc.)
- `Update-OrgProfileReadme.ps1` utility for generating GitHub org profile READMEs
- Test fixtures for Service Fabric ARM template export testing
- `.gitattributes` with union merge strategy for squad state files

### Changed
- `Export-ServiceFabricArmTemplate.ps1`: enhanced parameter handling and refactored
- `Publish-ToPublicRepo.ps1`: added try/finally cleanup, robocopy error handling, removed hardcoded local path
- `Export-AzCostReport.ps1`: fixed param-time evaluation bug, removed dead code branch

### Fixed
- `Import-CentralEnv.ps1`: replaced breaking mandatory `$Path` with deprecation warning and legacy default
- `Compare-AzProcessMemory.ps1`: fixed empty-array crash in `Get-StatObject` with proper null/count guard
- `Sync-VSCodeExtensionsToInsiders.ps1`: corrected `.EXAMPLES` to `.EXAMPLE` for Get-Help compatibility
