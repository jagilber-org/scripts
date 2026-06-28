# Contributing to jagilber-dev/scripts

## Dual-Repo Model

This repository follows a **dual-repo model**:

| Repo | Purpose | Visibility |
|------|---------|------------|
| `jagilber-dev/scripts` | Development repository | Private |
| `jagilber-org/scripts` | Public mirror | Public (read-only) |

`jagilber-dev/scripts` is the canonical development source for this project.
The public mirror at `jagilber-org/scripts` is a filtered, read-only copy that excludes private paths.

## Development Workflow

1. **Branch** from `main`
2. **Write tests first** (TDD: red-green-refactor)
3. **Implement** the change following `constitution.json` rules
4. **Run tests**: `.\Run-Tests.ps1`
5. **Run lint**: scripts must pass PSScriptAnalyzer
6. **Submit a PR** to `main`

## Publishing to Public Mirror

Use `Publish-ToPublicRepo.ps1` to publish to the public mirror:

```powershell
# Dry run (no push)
.\scripts\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0' -DryRun

# Publish with confirmation
.\scripts\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0'

# Publish without confirmation
.\scripts\Publish-ToPublicRepo.ps1 -Tag 'v1.0.0' -Force
```

The script reads `.publish-exclude` to determine which paths are stripped before
publishing. Private artifacts (`.specify/`, `specs/`, `.secrets.baseline`, etc.)
never reach the public mirror.

## Coding Standards

- **Approved verbs**: Use `Get-Verb` to verify function names
- **PascalCase**: All script and function names
- **Comment-based help**: `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`
- **CmdletBinding**: Required on all functions
- **PSScriptAnalyzer**: Zero errors required

## Testing

- Every script needs a Pester v5+ test in `tests/powershell/`
- Tests must include a `Script Validation` context
- Follow Arrange-Act-Assert pattern
- Tag integration tests with `'Integration'`
- Mock external dependencies

## Constitution

See `constitution.json` for the complete set of rules. Run
`.\sync-constitution.ps1` to regenerate the human-readable version at
`.specify/memory/constitution.md`.
