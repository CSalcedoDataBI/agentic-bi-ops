---
name: gh-account
description: Use FIRST before any GitHub Projects/issues operation in the agentic-bi-ops suite. Resolves which account (default CSalcedoDataBI, override PAL-Devs) and reads its PAT from the Windows user registry, injecting GH_TOKEN per-invocation without touching `gh auth switch`. Triggers — any board/issue op, "cambia a CSalcedoDataBI", 403 on a PAL board, INSUFFICIENT_SCOPES/read:project.
---

# gh-account — Cross-Account GitHub Token Resolver

**Purpose:** Every operation in this suite that touches GitHub Projects or issues must begin here. This skill ensures the right PAT is loaded into `GH_TOKEN` for the duration of that single operation — without ever calling `gh auth switch`, which would corrupt the user's global `gh` CLI state.

---

## Default account: CSalcedoDataBI — always

The default identity for all operations in this suite is **CSalcedoDataBI**, even when you are working inside a PAL-Devs-owned repository. The account only changes when the user explicitly says "use PAL-Devs" or you encounter a 403 on a PAL-owned board (see below).

---

## Canonical inline command (preferred — path-independent)

This is what the agent should run at the start of any operation. It reads from the Windows USER registry, which is always current (unlike `$env:`, which reflects the value at login time and may be stale).

**PowerShell (default — CSalcedoDataBI):**
```powershell
$t = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL', 'User')
$env:GH_TOKEN = $t
```

**PowerShell (PAL-Devs override):**
```powershell
$t = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_BUSINESS', 'User')
$env:GH_TOKEN = $t
```

`$env:GH_TOKEN` is read by `gh` automatically. Set it, run the `gh` command, and optionally clear it — never use `gh auth switch`.

**Bash equivalent (when running from a POSIX context):**
```bash
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
GH_TOKEN=$tok gh project list --owner CSalcedoDataBI --limit 5
```

For PAL-Devs, replace `GITHUB_TOKEN_PERSONAL` with `GITHUB_TOKEN_BUSINESS`.

---

## Convenience wrapper (with scope verification)

The helper script at `scripts/Get-GhAccount.ps1` (relative to the plugin root) wraps the inline command above and adds an automatic `project` scope check before returning the token object:

```powershell
$acct = & "${CLAUDE_PLUGIN_ROOT}/scripts/Get-GhAccount.ps1" -Account csalcedo
$env:GH_TOKEN = $acct.Token
# Now safe to run gh project / gh issue commands
```

For PAL-Devs:
```powershell
$acct = & "${CLAUDE_PLUGIN_ROOT}/scripts/Get-GhAccount.ps1" -Account pal-devs
$env:GH_TOKEN = $acct.Token
```

The script returns a `[pscustomobject]` with these fields:

| Field | Example |
|-------|---------|
| `Account` | `csalcedo` |
| `User` | `CSalcedoDataBI` |
| `Var` | `GITHUB_TOKEN_PERSONAL` |
| `Token` | `ghp_…` (handle with care; never log) |
| `Scopes` | `repo, project, read:org` |

If the Windows USER env var is missing, or if the token lacks `project` scope, the script writes an error and exits 1.

---

## Hard rules

- **Never run `gh auth switch`.** It changes the global `~/.config/gh/` state and will affect every subsequent `gh` call in the session, including operations unrelated to this suite.
- **Set `GH_TOKEN` only for the operation's scope.** After the `gh` call completes, you may clear it with `Remove-Item Env:GH_TOKEN` if other code in the same session must not inherit it.
- **Never print or log the raw token value.** The object `.Token` field exists only for assignment to `$env:GH_TOKEN`.

---

## Scope check

Before any board or Projects operation, confirm the token carries the `project` scope. The wrapper script does this automatically. If doing the inline command without the script, you can verify manually:

```powershell
$hdr = curl.exe -s -I -H "Authorization: token $env:GH_TOKEN" https://api.github.com/user
$hdr | Select-String 'x-oauth-scopes'
# Expected: x-oauth-scopes: repo, project, ...
```

If `project` is absent, tell the user: "Your PAT for [account] lacks the `project` scope. Go to GitHub → Settings → Developer settings → Personal access tokens and regenerate it with `project` checked."

---

## 403 on a PAL-owned board

If you receive a 403 while using the personal account (`CSalcedoDataBI`) on a board owned by `PAL-Devs` or `PAL-Devs/` repositories, this is an account mismatch. Instruct the caller to re-run the operation with `--account pal-devs`, which loads `GITHUB_TOKEN_BUSINESS` instead:

```powershell
$t = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_BUSINESS', 'User')
$env:GH_TOKEN = $t
# Retry the gh command
```

---

## Verified status

Verified 2026-06-26: both Windows USER env vars (`GITHUB_TOKEN_PERSONAL` for CSalcedoDataBI and `GITHUB_TOKEN_BUSINESS` for PAL-Devs) exist on this machine and carry the `project` scope.
