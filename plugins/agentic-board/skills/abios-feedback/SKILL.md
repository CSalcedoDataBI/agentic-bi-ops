---
name: abios-feedback
description: Use when, while working in ANY project (especially a PRIVATE one), you notice a bug or improvement for the agentic-board tool itself. Captures it as a SANITIZED issue on the tool's OWN public repo/board — never touching the current project and never leaking private data. Triggers — "mejora para la herramienta", "esto es una mejora para agentic-board", "abios bug", "esto deberíamos arreglarlo en el plugin", a guard block, a recurring gh/board failure.
user-invocable: false
---

# abios-feedback — improvements flow back, private data never leaks

## How to invoke
Say it in natural language while in any repo: *"esto es una mejora para agentic-board"*,
*"abios bug: …"*, or *"arréglalo en el plugin"*. The agent then runs the flow below. (Once the
plugin is installed you can also reach it via the `/board` command for the board part.)

## The principle
The cause may be in a private project; the captured improvement must be **public-only** and must
land on the **tool's own** repo — not the project you are currently in.

## Anti-confusion rules (so it never targets the wrong project)
These are absolute:
1. **Target is a CONSTANT, not the current repo.** Always operate on `CSalcedoDataBI/agentic-board`.
   **NEVER** resolve the target with `gh repo view` of the working directory — that would be the
   private project you are standing in. Pass `--repo CSalcedoDataBI/agentic-board` explicitly.
2. **Identity is the personal account**, via [[gh-account]] (`GITHUB_TOKEN_PERSONAL`), **even if the
   current project is a PAL-Devs repo**. The tool's repo is personal.
3. **Do NOT git add / commit / write files in the current project** for this. Capture goes to the
   tool's repo only (an issue), never the cwd repo tree.
4. **Sanitize first** (next section). The guard in the tool's repo is the backstop, not the cwd.

## Step 1 — Abstract / sanitize
Describe ONLY the public tool — which skill/script/recipe is wrong and the correct behavior. Strip:
- ❌ private repo names, client/customer names, data values, row counts
- ❌ Fabric/Power BI workspace or model GUIDs, OneLake paths, local file paths
- ❌ secrets/tokens, internal URLs, screenshots of private data
- ✅ the public file (`skills/…`, `scripts/…`, `references/…`), the wrong command/flag, the right
  one, and a generic repro (e.g. "on any repo, `gh project delete` has no `--yes`").

## Step 2 — Capture as a sanitized issue on the tool's own board (PRIMARY, path-independent)
```bash
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
GH_TOKEN=$tok gh issue create --repo CSalcedoDataBI/agentic-board \
  --label tool-improvement --title "<sanitized title>" --body "<sanitized body>"
# add it to the tool's roadmap board (its own water):
GH_TOKEN=$tok gh project item-add 13 --owner CSalcedoDataBI --url "<issue url from above>"
```
This needs no local path and cannot hit the current project — the target is explicit.

## Step 3 — Implement the fix (only when you choose to), in the tool's clone
Do this deliberately, not from the private project tree:
```bash
cd "$env:ABIOS_HOME"   # set ABIOS_HOME once to your local agentic-board clone path
# edit skills/scripts/references, then commit — the guard runs automatically
```
If `ABIOS_HOME` is unset, ask the user for the clone path; do **not** guess or write into the cwd.
Also append a dated, sanitized note to `inbox/IMPROVEMENTS.md` in that clone (optional log).

## Safety backstop (you do not rely on discipline alone)
The tool's repo has a guard (`scripts/guard-no-private.ps1`, wired pre-commit + pre-push) that
**blocks** any commit/push whose added lines contain a secret pattern or a term from the local
`.abios/private-denylist.txt`. If it blocks you, it caught a leak — do not `--no-verify` unless you
have confirmed a genuine false positive. See [[gh-account]] for identity; projects-admin for board recipes.
