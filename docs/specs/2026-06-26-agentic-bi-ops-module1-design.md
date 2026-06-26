# Design — `agentic-bi-ops` · Module 1 (GitHub Projects + Issues governance)

- **Date:** 2026-06-26
- **Owner repo:** `CSalcedoDataBI/agentic-bi-ops` (public, MIT)
- **Status:** Approved (brainstorming) → pending implementation plan

## 1. Purpose

A public, reusable **Claude Code plugin** that lets an AI agent administer and automate
**GitHub Projects (v2) boards and issues** across multiple GitHub accounts, installable by
anyone via the plugin marketplace and global on the author's machine.

This is the umbrella `agentic-bi-ops` suite ("GitOps for BI, with AI agents"). **Module 1**
ships the foundation (cross-account identity) + GitHub Projects/issues governance. Later modules
(BI-specific: PBIP/Fabric git ops, semantic-model agents) are out of scope here and get their own
spec → plan cycles.

### Non-goals (Module 1)
- No BI/Power BI/Fabric-specific tooling yet.
- Does not replace the existing `plan-tracking` skill (which turns a plan into an epic). This suite
  is the broader, public generalization; it may reuse the anchoring rule but does not reimplement
  plan→epic.
- No GitHub App / OAuth flows — auth is via the user's existing Windows-stored PATs.

## 2. Distribution & install (Claude Code plugin)

The repo is a plugin marketplace. Layout:

```
agentic-bi-ops/
├─ .claude-plugin/
│  ├─ plugin.json          # manifest: name, version, description, author, license
│  └─ marketplace.json     # enables: /plugin marketplace add CSalcedoDataBI/agentic-bi-ops
├─ skills/
│  ├─ gh-account/SKILL.md          # FOUNDATION: cross-account token/identity resolver
│  └─ projects-admin/
│     ├─ SKILL.md                  # board + issue governance/automation
│     └─ references/
│        ├─ board-ops.md           # gh project recipes (project/field/view/link)
│        ├─ issue-ops.md           # issue create/label/sub-issue/link recipes
│        └─ automation.md          # actions/add-to-project CI template
├─ commands/board.md       # /board slash command (entry point)
├─ scripts/Get-GhAccount.ps1   # reads token from Windows user registry
├─ README.md
├─ LICENSE                 # MIT
└─ CHANGELOG.md
```

- **Others install:** `/plugin marketplace add CSalcedoDataBI/agentic-bi-ops` then enable the plugin.
- **Author installs the same way** → global across all projects; updates via `git pull` / `/plugin`.
- **Dev clone location:** `D:\PAL-TEMPORAL-REPORSITORIOS\agentic-bi-ops` (its own git repo, outside
  the veda repo).

## 3. `gh-account` — cross-account foundation

Single source of truth for "which identity + token am I using". Reused by every future module.

**Rules:**
1. **Default account is always `CSalcedoDataBI`**, even when operating inside a PAL-owned repo.
2. Token is read **from the Windows user registry** (never `$env:` which can be stale in an open
   session):
   - `CSalcedoDataBI` → `GITHUB_TOKEN_PERSONAL`
   - `PAL-Devs` → `GITHUB_TOKEN_BUSINESS`
   PowerShell: `[System.Environment]::GetEnvironmentVariable("<VAR>","User")`.
3. The resolved token is injected **per invocation** as `GH_TOKEN` for the `gh`/MCP call scope. It
   **never** runs `gh auth switch`, so the user's global `gh` state is left untouched.
4. **Scope check:** verify the token carries `project` scope before any board op; on failure emit an
   actionable error (how to regenerate the PAT / which scope is missing).
5. **Override:** `--account pal-devs` forces the PAL identity. If a board lives under the PAL org and
   the personal account hits **HTTP 403**, the skill detects it and suggests the override rather than
   failing silently.

**Verified pre-conditions (2026-06-26):** both `GITHUB_TOKEN_PERSONAL` and `GITHUB_TOKEN_BUSINESS`
exist in the Windows user environment and both carry the `project` scope.

## 4. `projects-admin` — Module 1 skill

Recipe-driven, using `gh project` + `gh issue` natively, plus the `github-business` MCP for native
sub-issues (since `gh` has no stable sub-issue command). All ops route their identity through
`gh-account`.

- **board-ops.md** — create/edit/close/copy/delete a project; create/list fields; create views;
  `gh project link` board⇄repo. Honors the author's field conventions: **Status / Priority / Target**.
- **issue-ops.md** — create issues with labels (idempotent `--force`), attach native sub-issues
  (REST `.id` ≠ issue number), full `https://…/blob/<branch>/…` links (no relative paths), create
  issues only in the `origin` repo/owner resolved (inherited hard rule from `speckit-taskstoissues`).
- **automation.md** — drop-in `actions/add-to-project@v1` (MIT) workflow template to auto-add
  issues/PRs to a board filtered by label, for CI-side automation.

## 5. `/board` command

User entry point. Sub-actions (parsed from natural language or args): `init` (create+link a board to
the current repo), `add` (issue/PR → board), `move` (set Status), `field` (set Priority/Target),
`bulk` (batch move/close/label), `automate` (install the CI workflow). Delegates to `projects-admin`.

## 6. Error handling & safety

- Missing token var or missing `project` scope → clear, actionable message; stop.
- **Destructive ops** (delete project, bulk close/move) → **dry-run first**, print the plan, require
  explicit confirmation before mutating.
- Writes only against the resolved target repo/owner — never a random/shared board.
- 403 on a PAL board with the personal account → suggest `--account pal-devs`.

## 7. Testing / verification

Skills are prose, so "tests" = verification, not unit tests:
- A **read-only smoke script** (`gh project list` / `gh project item-list`) confirming `gh-account`
  resolves a token with `project` scope for the chosen account.
- A **throwaway test project** where the mutating recipes are exercised once (init → add item →
  move Status → archive), never against real boards.
- A verification checklist in `projects-admin/SKILL.md` (account pinned? scope ok? links resolve?
  item visible on board? dry-run shown before destructive op?).

## 8. Module roadmap (out of scope, future specs)

- M2: PBIP/Fabric git ops (branch-per-report, TMDL diff review).
- M3: semantic-model review agents wired to the board.
- M4: release automation for BI artifacts.

Each is a separate spec → plan → implement cycle; the `gh-account` foundation is shared by all.
