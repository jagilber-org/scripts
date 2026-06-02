# Agent-Managed Scripts

This directory is owned by AI agents for script creation, updates, and maintenance.

## Rules

1. **No PII, secrets, or internal information** — all scripts must be fully generalized
2. **Stage via branch + PR** — agents create a feature branch and open a PR for human review; never push directly to `main`
3. **Pre-commit hooks enforce scanning** — `check-pii.ps1`, `check-env-leaks.ps1`, and `gitleaks` run on every commit
4. **Parameterize everything** — no hardcoded paths, subscription IDs, resource names, thumbprints, or IP addresses
5. **Follow repo conventions** — use existing naming patterns (Verb-Noun.ps1), include `.SYNOPSIS`/`.DESCRIPTION`/`.EXAMPLE` help blocks

## How Agents Reference Scripts

In the MCP Index Server, script entries use metadata pointers instead of embedding code:

```json
{
  "id": "script-example-tool",
  "title": "Example Tool Script",
  "body": "Description of what the script does, when to use it, parameters...",
  "metadata": {
    "scriptRepo": "jagilber-dev/scripts",
    "scriptPath": "agents/Example-Tool.ps1",
    "scriptUrl": "https://github.com/jagilber-dev/scripts/blob/main/agents/Example-Tool.ps1"
  }
}
```

## Directory Structure

Agents may create subdirectories for organization:

```
agents/
├── README.md           # This file
├── azure/              # Azure-specific agent scripts
├── diagnostics/        # Diagnostic and troubleshooting scripts
└── utilities/          # General-purpose utilities
```

## Validation Checklist (for PR reviewers)

- [ ] No PII, secrets, credentials, or customer-specific data
- [ ] All paths are parameterized (no hardcoded `C:\cases\...` or similar)
- [ ] Includes PowerShell help block (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`)
- [ ] Passes `gitleaks detect --no-git` scan
- [ ] Passes `hooks/check-pii.ps1` scan
