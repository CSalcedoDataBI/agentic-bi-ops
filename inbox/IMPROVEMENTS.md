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

## 2026-06-29 — a board must only hold items from its own repo (no cross-project mixing)
- **Where:** `references/best-practices.md`, `projects-admin/SKILL.md` (Anchoring).
- **Problem:** nothing technically stopped adding an issue from a different (private) project onto a
  public tool's board.
- **Fix (0.6.2):** hard rule + check before `item-add` — the item's source repo must equal the
  board's anchored repo; refuse otherwise. Keeps the public board 100% about the tool. Verified the
  tool's board #13 contains only `CSalcedoDataBI/agentic-board` items.

## 2026-06-29 — board visibility must match repo exposure (public showcase needs public board)
- **Where:** `references/board-ops.md`, `references/best-practices.md`.
- **Problem:** boards are Private by default; the public README/SHOWCASE linked to a Private board,
  so external visitors couldn't see it.
- **Fix (0.6.1):** documented `gh project edit --visibility PUBLIC` and the rule "a board linked from
  a public repo's docs must be Public". Applied to the tool's own board #13.

## 2026-06-29 — project-scan: exclude doc-noise dirs by default
- **Where:** `skills/project-scan/SKILL.md` Step 1.
- **Problem:** scanning `*.md` for `- [ ]` returned ~600 hits, ~99% of them content inside skill/agent
  definitions and templates — not real project work.
- **Fix (0.5.1):** default excludes `**/.claude/skills/**`, `**/.specify/**`, `**/templates/**`
  (plus build/data dirs) via a shared `$EXC`.

## 2026-06-29 — project-scan: code-marker regex matched the Spanish word "todo"
- **Where:** `skills/project-scan/SKILL.md` Step 1.
- **Problem:** `\b(TODO|...)\b` flagged "...TODO es string" (Spanish "todo" = everything) and lowercase
  words.
- **Fix (0.5.1):** case-sensitive + require the `TAG:` / `TAG(` / `TAG id:` convention:
  `\b(TODO|FIXME|HACK|XXX|BUG)\b(\s*[:(]|\s+[A-Z0-9][\w-]*\s*:)`. Verified it catches real tags
  (`TODO:`, `TODO (F5):`, `TODO SM-107:`) and rejects bare-word "TODO es".

## 2026-06-26 — `init` should fill the board settings coherently
- **Where:** `skills/projects-admin/references/board-ops.md`, `commands/board.md` (init).
- **Problem:** a freshly created board left Short description / README / linked repository empty,
  so the GitHub Project settings page looked unfinished/unprofessional.
- **Fix (shipped 0.3.0):** init now sets the short description and README (`gh project edit
  --description/--readme`) and links the repo (`gh project link`). Documented that two settings are
  UI-only with no `gh`/GraphQL mutation: the **Default repository** pick (among linked repos) and the
  **View name/layout** ("View 1" → Board, group by Status).

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
