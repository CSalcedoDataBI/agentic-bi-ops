---
name: projects-admin
description: Use to administer or automate a GitHub Projects (v2) board or its issues — create/configure a project, set Status/Priority/Target fields, add/move/bulk-edit items, link a board to a repo, install CI auto-add, run /board fill to detect and fix gaps, or /board work to see pending issues across boards and start one. Always resolves identity via gh-account (default CSalcedoDataBI). Triggers — "administra el board", "mueve a Done", "crea el project", "add to board", "bulk close", "automatiza el board", "llena el board", "qué hay pendiente", "qué issue trabajo", "empecemos un issue", /board.
---

# projects-admin — GitHub Projects (v2) Board & Issue Admin

This skill covers the full lifecycle of a GitHub Projects v2 board and its items: creation, field setup, issue management, bulk operations, CI automation, and gap detection/fill via `/board fill`.

---

## Step 0 — Identity (always first)

**Before every operation in this skill, apply the `gh-account` skill** to load `GH_TOKEN` for the correct account. The default account is **CSalcedoDataBI**; switch to PAL-Devs only when the user explicitly says so or when you receive a 403 on a PAL-owned board.

```powershell
# Default — CSalcedoDataBI
$t = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL', 'User')
$env:GH_TOKEN = $t
```

Every `gh project` and `gh issue` command below assumes `$env:GH_TOKEN` is already set for the correct account. Never run `gh auth switch` — it mutates global `gh` state.

---

## Anchoring: one board, one repo

A board must be linked to exactly one origin repo before issue operations begin.

```powershell
# Resolve the origin repo (run inside the repo's working directory)
$origin = gh repo view --json nameWithOwner -q .nameWithOwner
# e.g. "CSalcedoDataBI/agentic-bi-ops"
```

Link or verify the link:

```powershell
gh project link <num> --owner <owner> --repo $origin
```

**Hard rule:** create issues ONLY in the `origin` owner/repo resolved above. Never write issues to a random shared board or unrelated repo.

**Hard rule — a board only holds items from its own repo.** Before `item-add`, the item's source
repo MUST equal the board's anchored repo. A board is about ONE project; never mix in issues from a
different (e.g. private) project. Verify and refuse otherwise:
```powershell
# the URL you are about to add must belong to the board's anchored repo
$anchored = "<owner>/<repo>"                      # the repo this board is linked to
if ($url -notmatch [regex]::Escape("github.com/$anchored/")) {
  throw "Refusing: $url is not from $anchored. Add it to that project's OWN board instead."
}
gh project item-add <num> --owner <owner> --url $url
```
This keeps a public tool's board free of any private-project content (and vice versa).

---

## Field conventions

All boards in this ecosystem use three single-select fields with these exact names:

| Field | Purpose | Typical options |
|-------|---------|----------------|
| **Status** | Workflow stage (kanban column) | `Todo`, `In Progress`, `Done`, `Blocked` |
| **Priority** | Urgency / triage | `P0`, `P1`, `P2` |
| **Target** | Milestone / sprint target | Sprint labels or date strings |

For the exact commands to create these fields and set their values on items, see `references/board-ops.md`.

---

## /board fill — Detect and fill column gaps

Scans the board for missing values (assignees, Status) and fills them. In CI it runs `scripts/board-sync.sh`; in interactive sessions it runs the PowerShell sequence below.

| Variant | Behavior |
|---------|----------|
| `/board fill` | Shows a full plan and asks for confirmation before acting |
| `/board fill --dry-run` | Prints what would change, executes nothing |
| `/board fill --auto` | Fills without asking — for CI or when the user has already approved |

### What gets filled

| Column | Fill rule |
|--------|-----------|
| **Assignees** | If empty, assign the board owner (`$OWNER`) |
| **Status** | Issue closed → `Done`; PR merged → `Done`; open PR + Status=Todo → `In Progress` |
| **Linked PRs** | System-derived by GitHub from PR mentions — not writable via API |
| **Sub-issues progress** | System-derived from closed sub-issues — not writable via API |

### Interactive mode (Claude Code session)

```powershell
# 1. Load token
$t = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL', 'User'); $env:GH_TOKEN = $t

# 2. Read all board items via GraphQL
$proj = gh api graphql -f query='
query($owner:String!, $num:Int!) {
  user(login:$owner) {
    projectV2(number:$num) {
      id
      items(first:100) {
        nodes {
          id
          fieldValues(first:20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue { field { ... on ProjectV2SingleSelectField { name } } optionId }
            }
          }
          content {
            ... on Issue { number state title assignees(first:5) { nodes { login } } }
          }
        }
      }
      fields(first:30) {
        nodes { ... on ProjectV2SingleSelectField { id name options { id name } } }
      }
    }
  }
}' -F owner=<owner> -F num=<project-num>

# 3. Detect gaps — items missing assignee or Status
# 4. --dry-run: print plan
# 5. --auto or after confirmation: execute
#    a) Empty assignee
gh issue edit <issue-num> --repo <owner>/<repo> --add-assignee <owner>
#    b) Wrong / missing Status
gh api graphql -f query='mutation(...) { updateProjectV2ItemFieldValue(...) { projectV2Item { id } } }' ...
```

### CI mode (GitHub Actions)

The workflow `.github/workflows/board-sync.yml` runs `bash scripts/board-sync.sh` automatically on every issue or PR event. This is equivalent to `/board fill --auto` with no manual intervention.

Triggers already configured:
```yaml
on:
  issues:    [opened, closed, reopened, assigned]
  pull_request: [opened, closed]
  schedule:  # Monday 9am UTC — weekly health check
  workflow_dispatch:
```

---

## /board work — See pending work and start an issue

The daily driver: answers "¿qué hay pendiente?" and starts the chosen issue. Runs
`scripts/Board-Work.ps1` in a conversational flow — steps 0–1 are questions the agent must ASK
and wait for; never assume the account or the scope:

| Step | Command | What it does |
|------|---------|--------------|
| 0. Ask account | (registry check, no script) | If BOTH `GITHUB_TOKEN_PERSONAL` and `GITHUB_TOKEN_BUSINESS` exist in the Windows USER registry, ask which account (personal = default); only one → use it silently. Business → pass `-TokenVar GITHUB_TOKEN_BUSINESS -Owner PAL-Devs` everywhere |
| 1. Ask scope | `git remote get-url origin` | Inside a GitHub repo clone, ask: boards of THIS repo or ALL boards of the account? Outside a repo, skip the question (= all) |
| 2. Pick a board | `Board-Work.ps1 -ListBoards [-Repo <owner/name>]` | With `-Repo`: only boards LINKED to that repo (`repository.projectsV2`) — exactly one result skips this pick. Without: every board of the owner (backups excluded). Both show pending count (Todo or no Status) + URL, most pending first |
| 3. Pick an issue | `Board-Work.ps1 -ProjectNum <n>` | That board's pending items sorted by Priority; drafts flagged (convert via `/board fill` first) |
| 4. Start it | `Board-Work.ps1 -ProjectNum <n> -Start <issueNum> -Branch` | Status → In Progress, assign owner, create + checkout branch `issue-<num>-<slug>`, print full issue context (body, labels, sub-issues) |
| 5. Finish it | push branch → PR with `Closes #<num>` → `Board-ReviewGate.ps1 -Repo <owner/name> -PR <n>` → merge only on exit 0 | Review gate (GitHub flow: merge only after approval): requests Copilot review when available, waits for CI checks + review, reports decision/feedback/unresolved threads. Blocked = fix, push, re-run. Then GitHub fills **Linked pull requests** by itself |

Notes:
- Step 4 supports `-DryRun` (preview, no mutation). A CLOSED issue is refused with a reopen hint.
  It retries once (4s) if the issue was added to the board seconds ago (eventual consistency).
- After step 4, the agent continues working the issue in-session — the printed context is the briefing.
- **Step 5 is mandatory**: never commit board-tracked issue work directly to main. `Linked pull
  requests` and `Sub-issues progress` are system-derived, read-only columns — the ONLY way to fill
  Linked PRs is finishing through a PR that closes the issue; Sub-issues progress only applies to
  parent issues with native sub-issues (empty = not applicable, not a gap).
- **Review gate fallbacks** (in order): Copilot code review (auto-requested) → `second-opinion`
  skill as extra reviewer → explicit self-review of `gh pr diff` (must be stated honestly in the
  report). "No checks configured" counts as pass with a hint to run `/board automate`.
- `Board-ReviewGate.ps1 -Repo <owner/name> -InstallRuleset` (optional, once per repo) installs a
  ruleset requiring PRs into the default branch; repo admins keep bypass — never claim it blocks
  admins.
- `-Branch` skips branch creation (with a warning) when the cwd is not a clone of the issue's repo.
- Skip steps 1–2 when the user already named a board.
- The script respects an already-set `GH_TOKEN` (from gh-account); otherwise it reads `GITHUB_TOKEN_PERSONAL` (or the var given in `-TokenVar`).

---

## Routing table

| Intent | Reference file | Command family |
|--------|---------------|----------------|
| Get the repo's board (reuse, don't duplicate) | `references/best-practices.md` | `Resolve-Board.ps1` (use BEFORE create) |
| Create a new project board (only if none) | `references/board-ops.md` | via `Resolve-Board.ps1` → `gh project create` |
| Delete a board (backup first, always) | `references/best-practices.md` | `Backup-Board.ps1` → `gh project delete` |
| Link board to a repo | `references/board-ops.md` | `gh project link` |
| Create / list fields (Status, Priority, Target) | `references/board-ops.md` | `gh project field-create`, `gh project field-list` |
| Apply a whole field preset (EN/ES, custom values) | `references/field-presets.md` | `Apply-FieldPreset.ps1 -Lang en\|es` |
| Set a field value on an item | `references/board-ops.md` | `gh project item-edit` |
| Bulk-fill a custom field across ALL items (by rule) | `references/board-ops.md` | `scripts/Set-BoardField.ps1` |
| **Detect and fill board gaps** | **this file — `/board fill` section** | **`/board fill` / `--dry-run` / `--auto`** |
| **See pending work / start an issue** | **this file — `/board work` section** | **`Board-Work.ps1 -ListBoards` / `-ProjectNum` / `-Start`** |
| Manage views / inspect board | `references/board-ops.md` | `gh project view`, `gh project item-list` |
| Create an issue with a label | `references/issue-ops.md` | `gh issue create` |
| Create / ensure a label exists | `references/issue-ops.md` | `gh label create --force` |
| Add an existing issue/PR to the board | `references/issue-ops.md` | `gh project item-add` |
| Create a native sub-issue (parent→child) | `references/issue-ops.md` | `github-business sub_issue_write` (MCP) |
| Place a full GitHub URL link in issue body | `references/issue-ops.md` | inline in `--body` |
| Move an item's Status field | `references/issue-ops.md` + `references/board-ops.md` | `gh project item-edit` (single-select set) |
| Bulk move items to a status | `references/issue-ops.md` + `references/board-ops.md` | loop over `item-list` → `item-edit` |
| Bulk close issues | `references/issue-ops.md` | loop over `gh issue list` → `gh issue close` |
| Bulk label issues | `references/issue-ops.md` | loop over issues → `gh issue edit --add-label` |
| Install CI auto-add workflow | `references/automation.md` | drop-in YAML |
| Install issue forms + PR template | `Install-RepoTemplates.ps1` | copies `presets/templates/` into `.github/`, ensures form labels exist, never overwrites without `-Force` |
| Apply the label taxonomy | `Apply-LabelPreset.ps1` | idempotent `gh label create --force` from `presets/labels.json`; type labels feed Board-Fill, `blocked` feeds work; never deletes |
| Break a big issue into sub-issues | `Board-Breakdown.ps1 -Parent <n> -Tasks ...` | native sub-issues via `addSubIssue`; refuses a CLOSED parent; task-list checkboxes are the fallback for tiny pieces |

---

## Safe operations — MANDATORY (see `references/best-practices.md`)

These two rules are not optional and must be followed every time:

### 1. Resolve-or-reuse before creating a board (never duplicate)
Before `init`, `add`, or registering a plan, **resolve the existing board** instead of blindly
creating one — duplicate boards are the most common mistake:
```powershell
$num = & "${CLAUDE_PLUGIN_ROOT}/scripts/Resolve-Board.ps1" -Owner <owner> -Repo <owner>/<repo>
# reuses the repo's board (canonical title "<repo> — Roadmap" or one containing the repo name),
# creating + linking + describing only if none exists. NEVER call `gh project create` directly.
```

### 2. Always back up before deleting (unconditional, do NOT ask)
Any `gh project delete` MUST be preceded by a full backup — automatically, without asking:
```powershell
& "${CLAUDE_PLUGIN_ROOT}/scripts/Backup-Board.ps1" -Number <num> -Owner <owner>
# writes a JSON snapshot (project+fields+items) AND a restorable live clone, THEN you may delete.
```
The backup happens unconditionally; the **delete** itself still needs explicit user confirmation.

## Safety — destructive operations require dry-run + confirmation

Before running any operation that mutates more than one item (bulk move, bulk close, bulk label, project delete), you MUST:

1. **Print the plan**: list every item that would be affected (title, number, current state).
2. **Pause and ask the user** to confirm before proceeding (the backup in rule 2 above already ran).
3. Only after explicit confirmation, run the mutation.

Example pattern for bulk close:

```powershell
# Step 1 — dry run: show what would close
$issues = gh issue list --repo $origin --state open --label board --json number,title | ConvertFrom-Json
$issues | ForEach-Object { Write-Host "Would close #$($_.number): $($_.title)" }

# Step 2 — confirm
# Ask user: "Ready to close these N issues? (yes/no)"

# Step 3 — execute only after "yes"
$issues | ForEach-Object { gh issue close $_.number --repo $origin }
```

The same dry-run pattern applies to `gh project delete` and any bulk `item-edit` loop.

---

## Relation to plan-tracking

This skill does **NOT** reimplement the `plan-tracking` skill. `plan-tracking` handles the workflow of turning a written plan document into a tracked GitHub epic with child issues (plan→epic). The present skill is general board administration — field setup, item moves, issue CRUD, CI automation — and can be used independently of any plan.

If you need to turn a plan into an epic, invoke the `plan-tracking` skill. If you need to move items on a board or configure project fields after that, use this skill.

---

## Verification checklist

Before reporting a board operation as complete, confirm:

- Account pinned and `project` scope verified? (`gh-account` step 0 done)
- Board linked to THIS repo, not to a random or shared board?
- Any links placed in issue bodies or project descriptions are full `https://github.com/<owner>/<repo>/blob/<branch>/...` URLs (never relative paths)?
- Added items are visible on the board after `gh project item-add` (spot-check with `gh project item-list`)?
- Dry-run was shown to the user and confirmed before any destructive op?
- **Resolve-or-reuse was used (no new duplicate board created)?**
- **A backup ran (JSON + live clone) BEFORE any `gh project delete`?**