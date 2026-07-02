# Changelog

## [0.11.0] - 2026-07-02
### Added
- **M4.2 — Changelog generation from board items** (`scripts/Board-Changelog.ps1`, `/board
  changelog`): turns the board's Done issues into a Keep-a-Changelog version block, grouping
  them into Added / Changed / Fixed by the board Type field (Feature→Added, Bug→Fixed,
  Docs/Refactor/Chore→Changed; label fallback when Type is empty). Includes only issues closed
  since the most recent CHANGELOG entry AND not already cited as `(#n)`, so shipped work is
  never double-listed. Prints the block; `-Write` inserts it at the top of the CHANGELOG;
  `-Version` / `-Date` / `-Since` override the defaults (version read from `plugin.json`).

## [0.10.1] - 2026-07-02
### Fixed
- **Board-Fill.ps1 cross-account** (#75): the script pinned `GITHUB_TOKEN_PERSONAL`
  unconditionally, so `/board fill` could not operate on a business-account board even with
  `$env:GH_TOKEN` pre-set. Now takes a `-TokenVar` parameter (default `GITHUB_TOKEN_PERSONAL`)
  and respects a pre-set `$env:GH_TOKEN` instead of clobbering it — same contract as
  `Board-Work.ps1`.
- **Board-Fill.ps1 silent failure** (#75): when the project or repo failed to resolve (wrong
  account / missing `project` scope / bad number), the script sailed on and reported "Board
  completo. Sin gaps detectados." Now it aborts loudly with a non-zero exit and a clear message.

## [0.10.0] - 2026-07-02
### Added
- **M2.2 — TMDL diff review** (`scripts/Tmdl-DiffReview.ps1` + `tmdl-review` skill): parses a
  PBIP semantic model's `*.tmdl` before/after a change and classifies every schema change as
  **BREAKING** (table/column/measure/hierarchy/relationship/role deleted, column `dataType` or
  `sourceColumn` changed, column/measure renamed), **WARNING** (measure/partition expression
  changed, `summarizeBy` changed, object hidden, relationship `crossFilteringBehavior` changed)
  or **INFO** (additions, `formatString`/`displayFolder`/`lineageTag`). Two modes: PR mode
  (`-Repo -PR`, reads changed `*.tmdl` via the GitHub API — no clone) and local mode
  (`-Base -Head`, git diff). `-FailOnBreaking` exits 1 on breaking (M3.3 will use it);
  `-Json` emits the findings object.
- **Review-gate integration**: `Board-ReviewGate.ps1` runs the TMDL review automatically when a
  PR touches `*.tmdl` (warn-only — surfaces breaking changes without changing the gate verdict).

## [0.9.2] - 2026-07-02
### Added
- **M2.3 — Cross-account PR workflow** (`scripts/New-BoardPR.ps1`): one command closes the
  work loop on any BI repo regardless of which account owns it. Resolves the account from the
  repo OWNER (CSalcedoDataBI -> `GITHUB_TOKEN_PERSONAL`, PAL-Devs -> `GITHUB_TOKEN_BUSINESS`;
  `-TokenVar` forces one), verifies the login has push permission, pushes the branch through a
  one-shot credential helper (the stored remote is never rewritten and the token never appears
  on the command line or in logs), and opens the PR with `Closes #<n>` — or, on re-run, just
  pushes new commits to the already-open PR (the review-gate iteration loop). `-DryRun`
  previews everything. `/board work` step 5a, the `gh-account` skill, and the `-Start` closing
  message now point here.

## [0.9.1] - 2026-07-01
### Added
- **MS2.2 — Local session registry** (`.agentic-bi-ops/sessions.json`, gitignored, shared
  across worktrees next to the MAIN clone): every successful `-Start` records issue, branch,
  work path, session PID (the long-lived parent process), host and start time. The pending
  list now shows LIVE local sessions ("who works what, where"); dead-PID entries are pruned
  automatically on every read. Completes the multi-session awareness plan.

## [0.9.0] - 2026-07-01
### Added
- **MS2.1 — Automatic worktree mode**: when the working copy is busy (dirty tree or another
  `issue-*` branch — another Claude session active), `Board-Work.ps1 -Branch` no longer just
  refuses: it creates (or reuses) an isolated git worktree `../<repo>--issue-<n>` — the
  official parallel-sessions pattern — and prints where to continue the work, plus the
  `git worktree remove` cleanup for after the merge. Two/three sessions can now work different
  issues of the same repo without touching each other.

## [0.8.9] - 2026-07-01
### Added
- **MS1.2 — Dirty-tree guard** in `Board-Work.ps1 -Branch`: never switches branches under
  another session's feet. If the working copy has uncommitted changes or sits on another
  `issue-*` branch, the switch is refused with the exact `git worktree add` command to work
  the issue in an isolated worktree instead. Re-entry on the SAME issue branch stays allowed.

## [0.8.8] - 2026-07-01
### Added
- **MS1.1 — Multi-session issue lock** in `Board-Work.ps1 -Start`: refuses an issue already
  In Progress + assigned (another Claude session probably has it), showing the last
  `[abios-claim]` fingerprint comment. `-TakeOver` retakes deliberately (dead session /
  handoff) and posts a TAKEOVER claim. Every successful start posts a claim comment
  (hostname, PID, time, branch). GitHub is the lock — works across machines, not just local
  sessions. First piece of the multi-session awareness plan.

## [0.8.7] - 2026-07-01
### Added
- **`/board plan`** (`scripts/Board-Plan.ps1`): turn a plan into a tracked epic + NATIVE
  sub-issues on the repo board — a plan is done when its tasks are issues, not when a markdown
  exists. Two entry modes: plan interactively now, or parse an existing plan doc/plan-mode
  output. Ensures `plan`/`plan-task` labels, reuses `Board-Breakdown` for children,
  `Resolve-Board` for the board (never duplicates), registers epic + children, and hands off to
  `/board fill` + `/board work`. Absorbs the lessons of the personal plan-tracking skill
  (pushed-ref blob URLs only, substantial-tasks-only, current-repo-only) so the flow ships with
  the plugin.

## [0.8.6] - 2026-07-01
### Added
- **M5.7 — Dependency-aware `work`**: pending items labeled `blocked` show as `[BLOCKED]` and
  cannot be started; `-Start` refuses them and also checks native blocked-by dependencies
  (best-effort API), listing the open blocker. `-IgnoreBlocked` overrides a false positive.
  Closes the last M5 gap: every automatable GitHub best practice is now enforced by the tool.

## [0.8.5] - 2026-07-01
### Added
- **M5.6 — `/board update`** (`scripts/Post-BoardStatusUpdate.ps1`): posts a ProjectV2 status
  update (`createProjectV2StatusUpdate`). With no `-Body` it generates one from the live board:
  counts per Status + the next pending items by Priority. `-Status` supports
  ON_TRACK/AT_RISK/OFF_TRACK/COMPLETE/INACTIVE. First update posted on the tool's own board.

## [0.8.4] - 2026-07-01
### Added
- **M5.5 — Small-PR guard** inside the review gate: measures the PR (files, +/- lines) and
  warns over 600 lines / 20 files (tunable `-MaxLines`/`-MaxFiles`), suggesting a
  `Board-Breakdown.ps1` split. A warning, never a block — GitHub PR BP: small focused PRs
  review better and introduce fewer bugs.

## [0.8.3] - 2026-07-01
### Added
- **M5.4 — Sub-issue breakdown** (`scripts/Board-Breakdown.ps1`, wired into work step 4): break
  a large issue into NATIVE sub-issues (`addSubIssue`) so the board's *Sub-issues progress*
  column fills itself as children close. Children get the `task` label and a "Part of #parent"
  body; a CLOSED parent is refused. Task-list checkboxes remain the documented fallback for
  pieces too small to be issues.

## [0.8.2] - 2026-07-01
### Added
- **M5.3 — `/board labels`** (`scripts/Apply-LabelPreset.ps1` + `presets/labels.json`):
  idempotent label taxonomy for any repo. Wired to the suite: `bug`/`docs`/`refactor`/`chore`
  are exactly what Board-Fill Type detection reads, `blocked` is what the work dependency check
  (M5.7) reads, `roadmap`/`plan`/`plan-task` are what plan tracking uses. Never deletes labels.

## [0.8.1] - 2026-07-01
### Added
- **M5.2 — `/board templates`** (`scripts/Install-RepoTemplates.ps1` + `presets/templates/`):
  installs issue forms (`bug`/`feature`/`task` + `config.yml`) and a `PULL_REQUEST_TEMPLATE.md`
  with the mandatory `Closes #` slot into the current repo's `.github/`. Ensures the labels the
  forms reference exist (GitHub silently ignores a form label that doesn't) — `bug` feeds the
  Board-Fill Type detection directly. Existing files are skipped unless `-Force`; the script
  only touches the working copy, committing goes through the normal (PR) flow. Installed on this
  repo as the first consumer.

## [0.8.0] - 2026-07-01
### Added
- **M5.1 — Review gate before merge** (`scripts/Board-ReviewGate.ps1` + work step 5b): no PR
  merges blind anymore. The gate requests a GitHub Copilot code review when available, waits for
  CI checks, waits for the review, prints decision + feedback + unresolved threads, and only
  exit 0 allows the merge. Fallback chain, stated honestly: Copilot → `second-opinion` skill →
  explicit self-review of `gh pr diff`. Closes the only RED gap in the GitHub-flow compliance
  matrix (merge only after approval).
- `Board-ReviewGate.ps1 -InstallRuleset` (optional, once per repo): repository ruleset requiring
  PRs into the default branch; repo admins keep bypass (documented — the hard gate for the agent
  is the work flow itself).

## [0.7.7] - 2026-07-01
### Fixed
- **Destructive false positive in the Status heuristic** (Board-Fill.ps1 AND the board-sync.sh
  CI variant): any merged PR that merely MENTIONED an issue number in its text (e.g. the words
  "board #13" in a PR body) counted as a linked PR and moved that untouched issue to Done — and
  the board's built-in "Done -> close issue" workflow then closed the real issue. Both scripts
  now count only CLOSING references (`willCloseTarget` on the cross-referenced event), for the
  merged->Done rule and the open-PR->In Progress rule alike. Found dogfooding the M5 plan.

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
