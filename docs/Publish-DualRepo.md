# Publish-DualRepo.ps1

Generalized dual-repo publishing script for the private-dev / public-publication repository pattern.

## Overview

Copies a private dev repository to a temp directory, strips internal artifacts using a
`.publish-exclude` file, verifies no sensitive content leaked via a forbidden-items safety
net, then force-pushes to a configured public git remote.

**No PAT required** - uses the developer normal git credentials.

## Location

- **Script**: [powershell/automation/Publish-DualRepo.ps1](../powershell/automation/Publish-DualRepo.ps1)
- **Tests**: [tests/powershell/Publish-DualRepo.Tests.ps1](../tests/powershell/Publish-DualRepo.Tests.ps1)

## Usage

```powershell
# Publish with a version tag
.\Publish-DualRepo.ps1 -Tag v1.0.0

# Dry run - preview what would be published
.\Publish-DualRepo.ps1 -DryRun

# Publish even if working tree is dirty
.\Publish-DualRepo.ps1 -Tag v2.1.0 -Force

# Use a custom remote name and exclusion file
.\Publish-DualRepo.ps1 -Tag v1.0.0 -RemoteName "github-public" -ExcludeFile ".my-excludes"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| -Tag | string | - | Version tag (e.g., v1.0.0). Required unless -DryRun. |
| -DryRun | switch | - | Preview files without publishing. |
| -Force | switch | - | Skip dirty-tree check. |
| -RemoteName | string | public | Git remote name for the public repo. |
| -ExcludeFile | string | .publish-exclude | Path to exclusion list file. |
| -ForbiddenItems | string[] | (see below) | Safety-net list of names that must NOT appear in output. |

### Default ForbiddenItems

.specify, specs, state, logs, backups, feedback, governance, memory,
metrics, snapshots, tmp, test-results, coverage, seed, .secrets.baseline,
.pii-allowlist, instructions, devinstructions, .private

## .publish-exclude Format

One path per line. Lines starting with # are comments. Blank lines are ignored.

### Pattern Types

| Pattern | Example | Matches |
|---------|---------|---------|
| Directory (ends with /) | instructions/ | All files under instructions/ |
| Exact file | build-output.txt | That specific file only |
| Prefix glob (ends with *) | .test-run-complete.* | Files starting with .test-run-complete. |

## How It Works

1. **Locate repo root** - walks up from script location to find .git
2. **Validate** - checks remote exists, tree is clean (unless -Force)
3. **Load exclusions** - parses .publish-exclude
4. **Copy to temp dir** - recursive copy, skipping .git and excluded paths
5. **Leak check** - Test-LeakedArtifacts scans for forbidden items
6. **Dry run or publish** - list files (-DryRun) or git init/commit/force-push
7. **Tag** - applies version tag on the public remote
8. **Cleanup** - removes temp directory

## Prerequisites

- Git CLI installed and on PATH
- PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
- Git remote configured: git remote add public https://github.com/owner/repo.git
- .publish-exclude file in repo root
- Push access to the public repository

## Pre-Push Hook Integration

The script sets PUBLISH_OVERRIDE=1 during the force-push to bypass pre-push-public-guard
hooks that block pushes to public repos. This ensures only authorized publishes reach the
public remote.

## Running Tests

```powershell
Invoke-Pester -Path tests\powershell\Publish-DualRepo.Tests.ps1 -Output Detailed
```
