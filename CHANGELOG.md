# Changelog

## [0.7.6] - 2026-07-01
### Added
- **`/board work` is now interactive about account and scope** (feedback from real use — it
  listed all account boards without asking anything):
  - **Step 0 — account**: if both `GITHUB_TOKEN_PERSONAL` and `GITHUB_TOKEN_BUSINESS` are
    configured, the agent asks which account to use (personal = default); with a single
    configured account there is no question.
  - **Step 1 — scope**: inside a repo clone the agent asks "boards of THIS repo or ALL boards
    of the account?". New `Board-Work.ps1 -ListBoards -Repo <owner/name>` lists only the boards
    LINKED to that repository (`repository.projectsV2`, per-board owner aware); exactly one
    linked board skips the board pick entirely.
- `-Start` now retries once (4s) when the issue was added to the board seconds earlier and is
  not yet visible in the items query (GitHub eventual consistency).
### Fixed
- Restored the `/board init` bullet in `board.md` — it had been mangled into the `work` section
  when 0.7.4 inserted it.

## [0.7.5] - 2026-07-01
### Added
- **Branch + PR finish flow in `/board work`** so the board's *Linked pull requests* system
  column always fills itself: `-Start` now accepts `-Branch` (creates + checks out
  `issue-<num>-<slug>` when the cwd is a clone of the issue's repo), and the flow mandates
  finishing through a PR whose body contains `Closes #<num>` — never a direct commit to main for
  board-tracked issues. Documented that *Linked pull requests* / *Sub-issues progress* are
  system-derived read-only columns: empty Sub-issues progress on a childless issue means "not
  applicable", not a gap.

## [0.7.4] - 2026-07-01
### Added
- **`/board work` — the daily driver** (menu option 1) + `scripts/Board-Work.ps1`: see what's
  pending and start working it. Three modes: `-ListBoards` shows EVERY board of the account with
  its pending count (Todo or no Status) and URL; `-ProjectNum <n>` lists that board's pending
  items sorted by Priority (drafts flagged — convert with `/board fill` first); `-ProjectNum <n>
  -Start <issueNum>` moves the item to In Progress, assigns the owner, and prints the full issue
  context (body, labels, sub-issues) so the agent starts working it in-session. `-DryRun`
  previews the start without mutating; a CLOSED issue is refused with a reopen hint. Respects an
  already-set `GH_TOKEN` (gh-account / `-TokenVar GITHUB_TOKEN_BUSINESS` for the second account).
### Fixed
- Single-select mutations in `Board-Fill.ps1`/`Board-Work.ps1` now pass the option id with
  `gh -f` (raw string) instead of `-F`: option ids are 8-hex-digit strings, and when one happens
  to be all-numeric (e.g. `98236657`) `-F` auto-types it as Int and GraphQL rejects the
  `String!` variable. Found dogfooding `/board work` on the tool's own board.

## [0.7.3] - 2026-06-30
### Added
- `Board-Fill.ps1` now fills **Priority** (P2 Medium), **Size** (M), and **Type** (from labels,
  else Feature) besides assignees/Status; local vars prevent PSObject expansion in `gh -F` args.

## [0.7.2] - 2026-06-30
### Added
- `scripts/Board-Fill.ps1` — interactive gap detection and fill for a whole board, with
  `-DryRun` / `-Auto` modes; converts draft notes to real issues before filling.

## [0.7.1] - 2026-06-30
### Added
- `/board fill` subcommand wired into `projects-admin` + the numbered menu shown when `/board`
  runs without arguments; the board URL is always printed in script output and responses.

## [0.7.0] - 2026-06-30
### Added
- **Bulk-fill a custom field across every board item by rule** — new `scripts/Set-BoardField.ps1`
  + `/board field` recipe. Single-select by title-prefix map (e.g. `Categoria`) or text by `{title}`
  template (e.g. `Ruta`), idempotent, retries transient 502s. Documents the gotchas that bite a manual
  loop (the `cat`=Get-Content alias shadowing, single-select-id vs `--text`, lowercased field keys in
  `item-list`, GraphQL-batch quoting). Turns the "fill all the columns" chore into one command.
- **Post-fill view-visibility warning** in `Set-BoardField.ps1`: after filling, it checks whether the
  field is shown in ANY board view and warns if not — the top "the tool didn't work" false alarm is a
  filled field that the current view simply doesn't display (view columns are UI-only; no API can add
  them). Also documents that `Assignees`/`Linked PRs`/`Sub-issues progress` are auto-derived system
  columns that stay blank on draft cards and cannot be filled by any tool.

## [0.6.2] - 2026-06-29
### Added
- Hard rule + pre-`item-add` check: a board only accepts items from its own anchored repo — a public
  tool's board can never be contaminated with private-project issues (and vice versa).

## [0.6.1] - 2026-06-29
### Fixed
- Board visibility guidance: a board linked from a public repo's docs/showcase must be Public
  (`gh project edit --visibility PUBLIC`). Documented in board-ops + best-practices; applied to the
  showcase board so its links work for everyone.

## [0.6.0] - 2026-06-29
### Added
- `scripts/Export-BoardSnapshot.ps1` — render any board as a Markdown table (a publishable snapshot).
- `SHOWCASE.md` — a self-contained, publishable example: the tool governing its own roadmap board,
  with the dogfooding loop and version evolution. No other repository referenced.

## [0.5.1] - 2026-06-29
### Fixed
- `project-scan` defaults: exclude doc-noise dirs (`.claude/skills`, `.specify`, `templates`) that
  drowned checklist results, and tighten the code-marker regex (case-sensitive + `TAG:`/`TAG(`
  convention) so the Spanish word "todo" and lowercase words are no longer false positives.

## [0.5.0] - 2026-06-26
### Added
- **Safe by design.** `scripts/Backup-Board.ps1` — a COMPLETE backup (JSON snapshot of
  project+fields+items + a restorable live clone) that runs **unconditionally before any board
  delete** (not asked).
- `scripts/Resolve-Board.ps1` — **find-or-reuse** the repo's board so `init`/`add`/plan never create
  a duplicate (fixes the "new board every time" bug). Creates+links+describes only if none exists.
- `references/best-practices.md` — methodology (Kanban base + Scrum-lite fields = Scrumban) and the
  enforced safe-operation rules, with sources.
### Changed
- `projects-admin` SKILL, board-ops, and `/board` now mandate resolve-before-create and
  backup-before-delete; verification checklist updated.

## [0.4.0] - 2026-06-26
### Added
- **Field presets** (`presets/fields.{en,es}.json` + `scripts/Apply-FieldPreset.ps1` +
  `references/field-presets.md`): one-step, idempotent, localized governance fields
  (Status/Priority/Type/Area/Estimate/Target). `/board field apply en|es`.
- **`project-scan` skill + `/scan` command**: scans the CURRENT project for untracked work
  (code TODO/FIXME, doc checklists & "pending" sections, plan/spec docs) and converts chosen items
  into issues + a board plan. Targets the current repo (not the tool's), propose-then-confirm.
### Notes
- Documented that view visibility/layout and renaming the built-in Status field are UI/GraphQL-only.

## [0.3.1] - 2026-06-26
### Changed
- `abios-feedback` hardened with explicit anti-confusion rules: capture is a sanitized issue on the
  CONSTANT target `CSalcedoDataBI/agentic-bi-ops` (never `gh repo view` of the cwd), personal account
  always, no writes to the current project; implementing happens in `$ABIOS_HOME`, not the cwd.

## [0.3.0] - 2026-06-26
### Added
- Coherent `board init`: now also sets the project's short description and README and links the repo
  (`gh project edit --description/--readme`, `gh project link`). Documents that the Default-repository
  pick and View name/layout are UI-only (no gh/GraphQL mutation).

## [0.2.1] - 2026-06-26
### Fixed
- Packaging: the plugin now lives in `plugins/agentic-bi-ops/` with its own `.claude-plugin/plugin.json`
  and the marketplace points to it (`source: ./plugins/agentic-bi-ops`). The previous root-as-plugin
  layout (`source: ./`) was silently rejected by `/plugin marketplace add`. Guard/dev-infra stays at root.

## [0.2.0] - 2026-06-26
### Added
- `abios-feedback` skill — capture tool improvements discovered in any project in a sanitized,
  public-only form (the dogfooding feedback flow).
- Private-content guard: `scripts/guard-no-private.ps1` + `hooks/{pre-commit,pre-push}` +
  `scripts/install-guard.ps1` — blocks any commit/push containing secrets or terms from the
  local-only `.abios/private-denylist.txt`.
- `inbox/IMPROVEMENTS.md` for sanitized improvement notes.
### Changed
- Internal dev docs (`docs/`) are no longer tracked in the public repo (kept local).

## [0.1.0] - 2026-06-26
### Added
- `gh-account` foundation skill (cross-account token resolution, default CSalcedoDataBI).
- `projects-admin` skill + references (board-ops, issue-ops, automation).
- `/board` command.
- Plugin manifest + marketplace entry.
- fix: exclude self-matching lines from secret guard pattern (#1)
