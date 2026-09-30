# Secret Incident Response Procedure

> When the pre-commit scanner blocks a commit containing a real secret, follow this procedure.
> **Principle**: Treat any detected secret as potentially compromised.

---

## Severity Levels

| Level | Condition | Response Time |
|-------|-----------|---------------|
| 🔴 **CRITICAL** | Secret was pushed to remote (hook bypassed) | Immediate |
| 🟡 **ELEVATED** | Secret in staged diff, not pushed, but may have leaked (shell history, logs, temp files) | Same day |
| 🟢 **LOW** | Secret in staged diff, hook caught it, no other exposure | Document only |

---

## Response Steps

### 🔴 CRITICAL — Secret Reached Remote

1. **Rotate immediately** — Generate a new credential in the issuing service
2. **Update central .env** — Replace the old value
3. **Reload** — `Import-CentralEnv -Force`
4. **Scrub git history** — Use `git filter-repo` or BFG Repo-Cleaner to remove the secret from all commits
5. **Force push** — Push the cleaned history (coordinate with team)
6. **Audit** — Check service logs for unauthorized use of the old credential
7. **Document** — Log the incident (see template below)

### 🟡 ELEVATED — Not Pushed, But Exposure Possible

1. **Assess exposure**:
   - Was the secret echoed in terminal output?
   - Is it in shell history? (`~/.bash_history`, `(Get-History)`)
   - Was it written to a log file or temp file?
   - Was the file open in an editor with cloud sync?
2. **If exposure confirmed**: Rotate → Update .env → Reload
3. **If exposure unlikely**: Remove from staged files, proceed with clean commit
4. **Document** — Log the near-miss

### 🟢 LOW — Hook Caught It, No Other Exposure

1. **Remove the secret** from the offending file
2. **Use `$env:VAR_NAME`** instead of hardcoding
3. **Re-stage and commit** normally
4. **Optionally document** for team awareness

---

## Rotation Quick Reference

| Secret Type | Where to Rotate | How |
|-------------|----------------|-----|
| Cloud storage key | Cloud portal → Storage → Access Keys → Regenerate | Regenerate Key 1 or Key 2 |
| Cloud service principal | Cloud portal → App Registration → Certificates & Secrets | Create new secret, delete old |
| Source control PAT | SCM Settings → Developer Settings → Tokens | Generate new, revoke old |
| AI API key | AI provider dashboard → API Keys | Create new, delete old |
| Connection string | Service portal → Connection Strings | Regenerate, update dependent apps |
| Certificate / PFX | Certificate authority or self-signed renewal | Issue new cert, update thumbprint |
| SAS token | Cloud portal → Storage → Shared Access Signature | Generate new SAS, old expires naturally |

---

## After Rotation

```powershell
# 1. Update the central .env with new value
code <root>\.env

# 2. Reload into current session
Import-CentralEnv -Force

# 3. Verify the new value works
$env:ROTATED_VAR_NAME  # confirm it's set

# 4. Test dependent services
# (run your smoke tests or connectivity checks)
```

---

## Incident Log Template

Use this template to document each incident. Store in a secure location (not in a git repo).

```
──────────────────────────────────────
Date:        YYYY-MM-DD HH:MM
Severity:    🔴 CRITICAL / 🟡 ELEVATED / 🟢 LOW
Secret Type: (e.g., Cloud storage key, API token)
Variable:    (e.g., $env:MY_SECRET_KEY — name only, NOT the value)
How Found:   (e.g., Layer 2 value match, Layer 3 pattern match)
Exposure:    (e.g., Pushed to remote / In staged diff only / Shell history)
Action:      (e.g., Rotated key, scrubbed history, documented)
Resolved:    Yes / No
Notes:       (any additional context)
──────────────────────────────────────
```

---

## Prevention Reminders

- **Never** hardcode secrets — always use `$env:VAR_NAME`
- **Never** bypass the hook without a genuine emergency (`--no-verify`)
- **If you must bypass**, run `Test-PreCommitPii.ps1 -DryRun` manually first
- **Rotate proactively** — if in doubt, rotate. The cost of rotation is always less than the cost of a breach.
