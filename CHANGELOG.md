# Changelog

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
