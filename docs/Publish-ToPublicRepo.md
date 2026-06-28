# Publish-ToPublicRepo.ps1

Publishes the canonical `jagilber-dev/scripts` development repository to the `jagilber-org/scripts` public mirror.

## Overview

Copies the repository to a temporary directory, strips private paths listed in
`.publish-exclude`, verifies no forbidden artifacts leaked, then force-pushes to the
public remote at `jagilber-org/scripts`.

**No PAT required** — uses the developer's normal git credentials.

## Location

- **Script**: [powershell/automation/Publish-ToPublicRepo.ps1](../powershell/automation/Publish-ToPublicRepo.ps1)
- **Tests**: [tests/powershell/Publish-ToPublicRepo.Tests.ps1](../tests/powershell/Publish-ToPublicRepo.Tests.ps1)

## Usage

```powershell
# Dry run — preview what would be published without pushing
.\powershell\automation\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0' -DryRun

# Publish with a version tag (prompts for confirmation)
.\powershell\automation\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0'

# Publish without confirmation prompt
.\powershell\automation\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0' -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| -Tag | string | — | Git tag to apply (e.g., `v1.0.0`). |
| -DryRun | switch | — | Preview without pushing. Temp directory is preserved. |
| -Force | switch | — | Skip confirmation prompt before pushing. |
| -RemoteUrl | string | `https://github.com/jagilber-org/scripts.git` | Public mirror remote URL. |

## How It Works

1. **Read `.publish-exclude`** — loads exclusion patterns from the repo root.
2. **Copy to temp dir** — uses `robocopy /MIR` to clone the repo, excluding `.git`.
3. **Strip excluded paths** — removes every entry matched by `.publish-exclude`.
4. **Leak check** — verifies that none of the forbidden artifact names (`.specify`, `specs`, `.secrets.baseline`) remain in the temp directory.
5. **Dry run or push** — if `-DryRun`, reports success and preserves temp dir; otherwise, inits a fresh git repo and `force-push`es to `HEAD:main`.
6. **Tag** — applies `-Tag` to the commit when provided.
7. **Cleanup** — removes the temp directory on success.

## .publish-exclude Format

One path per line. Lines beginning with `#` are comments. Blank lines are ignored.

```
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
