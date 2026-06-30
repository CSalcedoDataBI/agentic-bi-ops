# Changelog

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
- fix: fill board description, README and linked-repo on init (#6)
