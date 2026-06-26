# Improvements inbox

Sanitized, tool-only improvement notes captured via the `abios-feedback` skill. Each entry
describes a change to the **public** tool with **no** private project context. See
`skills/abios-feedback/SKILL.md` for the capture rules.

<!-- Newest first. Format:
## YYYY-MM-DD — short title
- **Where:** <public file or recipe>
- **Problem:** <generic, no private context>
- **Fix:** <concrete public change>
-->

## 2026-06-26 — plugin packaging: root-as-plugin is rejected by the installer
- **Where:** `.claude-plugin/marketplace.json`, repo layout.
- **Problem:** a single-plugin repo using `source: "./"` (plugin = repo root) is silently rejected
  by `/plugin marketplace add` — it never registers, so the slash command shows "Unknown command".
- **Fix (shipped 0.2.1):** the plugin must live in `plugins/<name>/` with its own
  `.claude-plugin/plugin.json`; the marketplace points to `./plugins/<name>`. Dev-infra (guard, hooks)
  stays at repo root.
- **Follow-up idea:** add a `validate-plugin-structure` check (CI or a guard step) that fails if
  `marketplace.json` references a plugin source that lacks `<source>/.claude-plugin/plugin.json`.

## 2026-06-26 — guard secret patterns self-matched their own definition lines
- **Where:** `scripts/guard-no-private.ps1`
- **Problem:** loose secret regexes matched the pattern-definition lines in the guard's own
  source (and a `+`-concatenated pattern split into fragments), blocking legitimate commits.
- **Fix:** every secret pattern leads with a character class so the source is never contiguous;
  no string concatenation in the pattern array. Shipped in 4c94aa7. (Tracked: issue #1)

## 2026-06-26 — `gh issue create` returns the URL on stdout, not via `--json url`
- **Where:** `skills/projects-admin/references/issue-ops.md`, `skills/abios-feedback/SKILL.md`
- **Problem:** scripting `gh issue create --json url -q .url` fails on the installed gh version.
- **Fix:** capture the URL straight from stdout (`url=$(gh issue create ...)`); do not pass `--json`
  to `issue create`. (Recipes already use plain stdout — keep it that way.)
