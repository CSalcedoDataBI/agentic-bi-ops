---
name: abios-feedback
description: Use when, while working in ANY project (especially a PRIVATE one), you notice a bug or improvement for the agentic-bi-ops tool itself. Captures the improvement in a SANITIZED, tool-only form so it can flow back to the public repo without ever leaking private project data. Triggers — "mejora para la herramienta", "esto del board falló", "abios bug", "esto deberíamos arreglarlo en el plugin", a guard block, a recurring gh/board failure.
---

# abios-feedback — improvements flow back, private data never leaks

## The principle
The public `agentic-bi-ops` repo **dogfoods itself** (its own improvements are tracked on its
own board). But most improvements are discovered while working inside **private** projects.
The rule is absolute: **the cause may be private; the captured improvement must be public-only.**

## When you spot a tool improvement

1. **Abstract it.** Describe ONLY the public tool — which skill/script/recipe is wrong and what
   the correct behavior is. Strip every trace of the private context:
   - ❌ NO private repo names, client/customer names, data values, row counts.
   - ❌ NO Fabric/Power BI workspace or model GUIDs, OneLake paths, local file paths.
   - ❌ NO secrets/tokens, internal URLs, or screenshots of private data.
   - ✅ YES the public file (`skills/…`, `scripts/…`, `references/…`), the wrong command/flag,
     the correct one, and a generic repro ("on any repo, `gh project delete` has no `--yes`").

2. **Record it in the PUBLIC clone**, never in the private project tree. Append a dated, sanitized
   entry to `inbox/IMPROVEMENTS.md` in `agentic-bi-ops`:
   ```markdown
   ## YYYY-MM-DD — <short title>
   - **Where:** <public file or recipe>
   - **Problem:** <generic description, no private context>
   - **Fix:** <the concrete public change>
   ```

3. **(Optional) dogfood it onto the tool's own board** using the plugin itself:
   ```bash
   # uses the personal account (the tool's own repo)
   tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
   GH_TOKEN=$tok gh issue create --repo CSalcedoDataBI/agentic-bi-ops \
     --title "<sanitized title>" --label tool-improvement --body "<sanitized body>"
   ```
   The issue text is subject to the same sanitization rule.

## The safety backstop (you do not rely on discipline alone)
The public repo has a guard (`scripts/guard-no-private.ps1`, wired as pre-commit + pre-push) that
**blocks** any commit/push whose added lines contain a known secret pattern or a term from the
local `.abios/private-denylist.txt`. If the guard blocks you, it caught a leak — do NOT bypass it
with `--no-verify` unless you have confirmed it is a genuine false positive.

## Applying the improvement
Implement the fix **in the public clone only**, let the guard run on commit/push, then it ships
to everyone via the plugin update. See [[gh-account]] for identity and the projects-admin
references for board recipes.
