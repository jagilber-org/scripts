# Publish-ToPublicRepo.ps1

Publishes the canonical `jagilber-dev/scripts` development repository to the `jagilber-org/scripts` public mirror.

## Overview

Copies files committed at the repository `HEAD` to a temporary directory, strips
private paths listed in `.publish-exclude`, verifies no forbidden or oversized
artifacts leaked, then force-pushes to the public remote at `jagilber-org/scripts`.
Ignored and untracked working-tree files are never published.

**No PAT required** — uses the developer's normal git credentials.

## Location

- **Script**: [powershell/automation/Publish-ToPublicRepo.ps1](../powershell/automation/Publish-ToPublicRepo.ps1)
- **Tests**: [tests/powershell/Publish-ToPublicRepo.Tests.ps1](../tests/powershell/Publish-ToPublicRepo.Tests.ps1)

## Usage

```powershell
# Dry run — preview what would be published without pushing
.\powershell\automation\Publish-ToPublicRepo.ps1 -DirectPublish -DryRun

# Publish with a version tag (prompts for confirmation)
.\powershell\automation\Publish-ToPublicRepo.ps1 -DirectPublish

# Publish without confirmation prompt
.\powershell\automation\Publish-ToPublicRepo.ps1 -DirectPublish -Force
```

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| -Tag | string | — | Git tag to apply (e.g., `v1.0.0`). |
| -DryRun | switch | — | Preview without pushing. Temp directory is preserved. |
| -Force | switch | — | Skip confirmation prompt before pushing. |
| -DirectPublish | switch | — | Publish the cleaned tree directly to the public mirror. |
| -CreateReviewRepo | switch | — | Create a private review repository instead of publishing publicly. |
| -LocalPath | string | — | Copy cleaned content to a local review directory. |
| -RemoteUrl | string | `https://github.com/jagilber-org/scripts.git` | Public mirror remote URL. |

## How It Works

1. **Read `.publish-exclude`** — loads exclusion patterns from the repo root.
2. **Copy to temp dir** — exports and expands the committed tree from `git archive HEAD`.
3. **Strip excluded paths** — removes every entry matched by `.publish-exclude`.
4. **Leak and size check** — verifies that no forbidden artifacts remain and that no file exceeds GitHub's 100 MB limit.
5. **Dry run or push** — if `-DryRun`, reports success and preserves temp dir; otherwise, inits a fresh git repo and `force-push`es to `HEAD:main`.
6. **Tag** — applies `-Tag` to the commit when provided.
7. **Push verification** — fails the command if Git rejects the public update.
8. **Cleanup** — removes the temp directory on success or failure.

## .publish-exclude Format

One path per line. Lines beginning with `#` are comments. Blank lines are ignored.

```text
# Internal tooling
.specify/
specs/

# Secret detection baseline
.secrets.baseline
```

## Prerequisites

- Git CLI available on `PATH`
- PowerShell 5.1 or PowerShell Core 7+
- Push access to `https://github.com/jagilber-org/scripts`
- `.publish-exclude` file present at the repository root

## See Also

- [Publish-DualRepo.ps1](../powershell/automation/Publish-DualRepo.ps1) — generalized dual-repo publishing with richer exclusion matching
- [CONTRIBUTING.md](../CONTRIBUTING.md) — full publishing workflow
