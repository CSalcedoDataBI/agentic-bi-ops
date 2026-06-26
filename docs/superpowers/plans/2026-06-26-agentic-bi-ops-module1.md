# agentic-bi-ops · Module 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `CSalcedoDataBI/agentic-bi-ops` as a public Claude Code plugin whose Module 1 administers/automates GitHub Projects (v2) boards and issues across two accounts, defaulting to the CSalcedoDataBI identity from Windows-stored PATs.

**Architecture:** A plugin-marketplace repo. A foundation skill `gh-account` resolves identity+token (registry-read, `GH_TOKEN` per-invocation, no `gh auth switch`). A `projects-admin` skill + `references/` hold the `gh project`/`gh issue`/MCP recipes. A `/board` command is the entry point. No app runtime — everything is markdown skills + one PowerShell helper.

**Tech Stack:** Claude Code plugin spec (`.claude-plugin/`), `gh` CLI (`gh project`, `gh issue`), `github-business` MCP (native sub-issues), PowerShell (token resolution on Windows), `actions/add-to-project` (CI template).

**Working dir:** `D:\PAL-TEMPORAL-REPORSITORIOS\agentic-bi-ops` (already `git init`-ed, local identity = CSalcedoDataBI, spec committed at `docs/specs/2026-06-26-agentic-bi-ops-module1-design.md`).

**Token for all pushes of THIS repo:** `GITHUB_TOKEN_PERSONAL` (CSalcedoDataBI). Push idiom:
```bash
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
git -c "url.https://$tok@github.com/.insteadOf=https://github.com/" push -u origin main
```

---

## File Structure

| File | Responsibility |
|------|----------------|
| `.claude-plugin/plugin.json` | Plugin manifest (name/version/desc/author/license) |
| `.claude-plugin/marketplace.json` | Marketplace entry so `/plugin marketplace add` works |
| `skills/gh-account/SKILL.md` | Foundation: account+token resolution rules (the canonical inline command) |
| `scripts/Get-GhAccount.ps1` | Convenience wrapper around the registry-read + scope-check |
| `skills/projects-admin/SKILL.md` | Board+issue governance, safety rules, verification checklist |
| `skills/projects-admin/references/board-ops.md` | `gh project` recipes (project/field/view/link) |
| `skills/projects-admin/references/issue-ops.md` | `gh issue` + MCP sub-issue + linking recipes |
| `skills/projects-admin/references/automation.md` | `actions/add-to-project` CI template |
| `commands/board.md` | `/board` slash command dispatch |
| `README.md` / `LICENSE` / `CHANGELOG.md` / `.gitignore` | Repo hygiene + MIT license + install docs |

---

### Task 1: Repo skeleton, manifests, license, create+push GitHub repo

**Files:**
- Create: `.gitignore`, `LICENSE`, `README.md`, `CHANGELOG.md`
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write `.gitignore`**

```
# editor / os
.DS_Store
Thumbs.db
*.log
# local scratch
/tmp/
/.local/
```

- [ ] **Step 2: Write `LICENSE` (MIT)**

Standard MIT text, `Copyright (c) 2026 CSalcedoDataBI`.

- [ ] **Step 3: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "agentic-bi-ops",
  "version": "0.1.0",
  "description": "GitOps for BI with AI agents. Module 1: cross-account GitHub Projects & issues governance.",
  "author": { "name": "CSalcedoDataBI" },
  "license": "MIT",
  "homepage": "https://github.com/CSalcedoDataBI/agentic-bi-ops"
}
```

- [ ] **Step 4: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "agentic-bi-ops",
  "owner": { "name": "CSalcedoDataBI", "url": "https://github.com/CSalcedoDataBI" },
  "plugins": [
    {
      "name": "agentic-bi-ops",
      "source": "./",
      "description": "Cross-account GitHub Projects & issues governance, plus future BI GitOps modules."
    }
  ]
}
```

- [ ] **Step 5: Write `README.md`**

Must contain: one-line pitch; **Install** (`/plugin marketplace add CSalcedoDataBI/agentic-bi-ops` → enable `agentic-bi-ops`); **Prerequisites** (`gh` CLI; Windows user vars `GITHUB_TOKEN_PERSONAL` and optionally `GITHUB_TOKEN_BUSINESS`, each a PAT with `project`+`repo` scopes); **What's inside** (gh-account, projects-admin, /board); **Module roadmap** (M2-M4); MIT badge.

- [ ] **Step 6: Write `CHANGELOG.md`**

```markdown
# Changelog

## [0.1.0] - 2026-06-26
### Added
- `gh-account` foundation skill (cross-account token resolution, default CSalcedoDataBI).
- `projects-admin` skill + references (board-ops, issue-ops, automation).
- `/board` command.
- Plugin manifest + marketplace entry.
```

- [ ] **Step 7: Commit**

```bash
cd "D:/PAL-TEMPORAL-REPORSITORIOS/agentic-bi-ops"
git add .gitignore LICENSE README.md CHANGELOG.md .claude-plugin/
git commit -m "chore: repo skeleton + plugin manifests + MIT license"
```

- [ ] **Step 8: Create the public GitHub repo (personal token) and push**

```bash
cd "D:/PAL-TEMPORAL-REPORSITORIOS/agentic-bi-ops"
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
GH_TOKEN=$tok gh repo create CSalcedoDataBI/agentic-bi-ops --public \
  --description "GitOps for BI with AI agents — cross-account GitHub Projects & issues governance" \
  --source . --remote origin --push=false
git branch -M main
git -c "url.https://$tok@github.com/.insteadOf=https://github.com/" push -u origin main
```
Expected: repo exists at https://github.com/CSalcedoDataBI/agentic-bi-ops with `main` pushed (spec + skeleton).

---

### Task 2: `gh-account` foundation skill + helper script + smoke test

**Files:**
- Create: `scripts/Get-GhAccount.ps1`
- Create: `skills/gh-account/SKILL.md`

- [ ] **Step 1: Write `scripts/Get-GhAccount.ps1`**

```powershell
<#  Get-GhAccount.ps1 — resolve GitHub account + token for agentic-bi-ops.
    Default account: CSalcedoDataBI. Override: -Account pal-devs.
    Reads the PAT from the Windows USER registry (not $env:, which can be stale).
    Verifies the 'project' scope. Emits an object with .Token to set $env:GH_TOKEN.  #>
[CmdletBinding()]
param([ValidateSet('csalcedo','pal-devs')][string]$Account = 'csalcedo')

$map = @{
  'csalcedo' = @{ User = 'CSalcedoDataBI'; Var = 'GITHUB_TOKEN_PERSONAL' }
  'pal-devs' = @{ User = 'PAL-Devs';       Var = 'GITHUB_TOKEN_BUSINESS' }
}
$sel   = $map[$Account]
$token = [System.Environment]::GetEnvironmentVariable($sel.Var, 'User')
if ([string]::IsNullOrWhiteSpace($token)) {
  Write-Error "Token var '$($sel.Var)' not found in Windows USER env for '$($sel.User)'. Create a PAT with 'project'+'repo' scopes and set it."
  exit 1
}
$hdr    = curl.exe -s -I -H "Authorization: token $token" https://api.github.com/user
$scopes = (($hdr | Select-String -Pattern '^x-oauth-scopes:' ) -replace '(?i)^x-oauth-scopes:\s*','').Trim()
if ($scopes -notmatch '\bproject\b') {
  Write-Error "Token for '$($sel.User)' lacks 'project' scope (has: $scopes). Regenerate the PAT with 'project'."
  exit 1
}
[pscustomobject]@{ Account=$Account; User=$sel.User; Var=$sel.Var; Token=$token; Scopes=$scopes }
```

- [ ] **Step 2: Write `skills/gh-account/SKILL.md`**

Frontmatter:
```markdown
---
name: gh-account
description: Use FIRST before any GitHub Projects/issues operation in the agentic-bi-ops suite. Resolves which account (default CSalcedoDataBI, override PAL-Devs) and reads its PAT from the Windows user registry, injecting GH_TOKEN per-invocation without touching `gh auth switch`. Triggers — any board/issue op, "cambia a CSalcedoDataBI", 403 on a PAL board, INSUFFICIENT_SCOPES/read:project.
---
```
Body must state, concretely:
- **Default = CSalcedoDataBI, always**, even inside PAL repos.
- **Canonical inline command (the agent uses THIS, path-independent):**
  ```powershell
  $t=[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User'); $env:GH_TOKEN=$t
  ```
  For PAL override: same with `GITHUB_TOKEN_BUSINESS`.
- **Convenience wrapper:** `& "${CLAUDE_PLUGIN_ROOT}/scripts/Get-GhAccount.ps1" -Account csalcedo` → `.Token`.
- **Never** run `gh auth switch` (leaves global state dirty); set `GH_TOKEN` only for the op.
- **Scope check** before board ops; fail with the regenerate-PAT message.
- **403 on PAL-owned board with personal account** → tell the user to re-run with `--account pal-devs`.
- Verified 2026-06-26: both Windows vars exist and carry `project`.

- [ ] **Step 3: Smoke test (read-only) — CSalcedoDataBI resolves a project-scoped token**

```bash
cd "D:/PAL-TEMPORAL-REPORSITORIOS/agentic-bi-ops"
powershell.exe -NoProfile -File scripts/Get-GhAccount.ps1 -Account csalcedo
```
Expected: an object printed with `User : CSalcedoDataBI` and `Scopes` containing `project`; exit 0.

- [ ] **Step 4: Smoke test — token actually lists projects**

```bash
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
GH_TOKEN=$tok gh project list --owner CSalcedoDataBI --limit 5
```
Expected: a (possibly empty) project list with NO `INSUFFICIENT_SCOPES` error.

- [ ] **Step 5: Commit**

```bash
git add scripts/Get-GhAccount.ps1 skills/gh-account/SKILL.md
git commit -m "feat(gh-account): cross-account token resolver (default CSalcedoDataBI)"
```

---

### Task 3: `projects-admin` skill + references

**Files:**
- Create: `skills/projects-admin/SKILL.md`
- Create: `skills/projects-admin/references/board-ops.md`
- Create: `skills/projects-admin/references/issue-ops.md`
- Create: `skills/projects-admin/references/automation.md`

- [ ] **Step 1: Write `skills/projects-admin/SKILL.md`**

Frontmatter:
```markdown
---
name: projects-admin
description: Use to administer or automate a GitHub Projects (v2) board or its issues — create/configure a project, set Status/Priority/Target fields, add/move/bulk-edit items, link a board to a repo, or install CI auto-add. Always resolves identity via gh-account (default CSalcedoDataBI). Triggers — "administra el board", "mueve a Done", "crea el project", "add to board", "bulk close", "automatiza el board", /board.
---
```
Body must contain:
- **Step 0 — identity:** invoke `gh-account` rules; set `GH_TOKEN` before anything.
- **Anchoring:** one board ⇄ one repo (`gh project link`); write issues ONLY in `origin` owner/repo.
- **Field conventions:** Status / Priority / Target (single-select). Reference `board-ops.md`.
- **Routing table:** intent → reference file → exact command family.
- **Safety:** destructive ops (`project delete`, bulk close/move) require a **dry-run print + explicit confirm**.
- **Relation to plan-tracking:** this skill does general admin; it does NOT reimplement plan→epic.
- **Verification checklist:** account pinned? `project` scope ok? links are full `blob/<branch>` URLs? item visible on board? dry-run shown before destructive op?

- [ ] **Step 2: Write `references/board-ops.md`** — concrete `gh project` recipes:

```bash
# create + link to current repo
gh project create --owner <owner> --title "<repo> — Board"
gh project link <num> --owner <owner> --repo <owner>/<repo>
# fields (Status/Priority/Target as single-select)
gh project field-create <num> --owner <owner> --name "Priority" --data-type SINGLE_SELECT \
  --single-select-options "P0,P1,P2"
gh project field-list <num> --owner <owner>
# views / list / item inspection
gh project view <num> --owner <owner> --web
gh project item-list <num> --owner <owner> --format json
```
Plus the GraphQL note: setting a single-select value needs `gh project item-edit --id <itemId> --field-id <fid> --single-select-option-id <oid>` (ids from `field-list --format json` + `item-list --format json`).

- [ ] **Step 3: Write `references/issue-ops.md`** — concrete recipes:

```bash
# idempotent labels
gh label create board --color 0E8A16 --force
# create issue in origin repo only
gh issue create --repo <owner>/<repo> --title "<t>" --label board --body "<b>"
# add issue/PR to board
gh project item-add <num> --owner <owner> --url <issueUrl>
# move Status: resolve ids then edit (see board-ops single-select note)
```
Plus: native sub-issue via MCP `github-business sub_issue_write` (`method:add`, `issue_number:<parent>`, `sub_issue_id:<child REST .id>` from `gh api repos/<owner>/<repo>/issues/<n> --jq .id`). Full `https://github.com/<owner>/<repo>/blob/<branch>/<path>` links only — no relative paths.

- [ ] **Step 4: Write `references/automation.md`** — drop-in workflow template:

```yaml
# .github/workflows/add-to-project.yml  (consumer repo)
name: Add issues/PRs to board
on:
  issues: { types: [opened, labeled] }
  pull_request: { types: [opened, labeled] }
jobs:
  add:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/add-to-project@v1
        with:
          project-url: https://github.com/users/<owner>/projects/<num>
          github-token: ${{ secrets.ADD_TO_PROJECT_PAT }}
          labeled: board        # only items with this label
```
Plus a note: the PAT secret needs `project` scope; org boards use `orgs/<org>/projects/<num>`.

- [ ] **Step 5: Lint the skill frontmatter (name matches folder, description present)**

```bash
cd "D:/PAL-TEMPORAL-REPORSITORIOS/agentic-bi-ops"
grep -Rl "^name:" skills/*/SKILL.md
```
Expected: lists `skills/gh-account/SKILL.md` and `skills/projects-admin/SKILL.md`.

- [ ] **Step 6: Commit**

```bash
git add skills/projects-admin/
git commit -m "feat(projects-admin): board+issue governance skill + references"
```

---

### Task 4: `/board` command

**Files:**
- Create: `commands/board.md`

- [ ] **Step 1: Write `commands/board.md`**

Frontmatter + body that maps sub-actions to `projects-admin`:
```markdown
---
description: Administer/automate a GitHub Projects board (init/add/move/field/bulk/automate). Defaults to the CSalcedoDataBI account.
---
You are running the agentic-bi-ops /board command. First apply the `gh-account` skill to set
GH_TOKEN (default CSalcedoDataBI; honor `--account pal-devs`). Then apply the `projects-admin`
skill. Parse the request into one of: init | add | move | field | bulk | automate, and run the
matching recipe from projects-admin/references. For destructive actions, show a dry-run and confirm.

Arguments: $ARGUMENTS
```

- [ ] **Step 2: Commit**

```bash
git add commands/board.md
git commit -m "feat(command): /board entry point"
```

---

### Task 5: End-to-end verification on a throwaway test project, then push

**Files:** none (verification only) — then docs touch-up.

- [ ] **Step 1: Create a throwaway test project (personal account)**

```bash
tok=$(powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')" | tr -d '\r')
GH_TOKEN=$tok gh project create --owner CSalcedoDataBI --title "abios-smoke-test"
GH_TOKEN=$tok gh project list --owner CSalcedoDataBI --format json | python -c "import sys,json;[print(p['number'],p['title']) for p in json.load(sys.stdin)['projects']]"
```
Expected: the new project number is printed.

- [ ] **Step 2: Exercise the mutating path once (add a draft item, then archive)**

```bash
# use the <num> from Step 1
GH_TOKEN=$tok gh project item-create <num> --owner CSalcedoDataBI --title "smoke item"
GH_TOKEN=$tok gh project item-list <num> --owner CSalcedoDataBI --format json
```
Expected: the draft item appears in the list.

- [ ] **Step 3: Tear down the test project (confirm destructive-op pattern works)**

```bash
GH_TOKEN=$tok gh project delete <num> --owner CSalcedoDataBI
```
Expected: deletion succeeds; `gh project list` no longer shows `abios-smoke-test`.

- [ ] **Step 4: Final commit + push to GitHub (personal token)**

```bash
cd "D:/PAL-TEMPORAL-REPORSITORIOS/agentic-bi-ops"
git add -A
git commit -m "docs: finalize module 1 (verified end-to-end)" --allow-empty
git -c "url.https://$tok@github.com/.insteadOf=https://github.com/" push origin main
```

---

### Task 6: Install the plugin locally (global) and confirm discovery

**Files:** none.

- [ ] **Step 1: Add the marketplace + install (in a Claude Code session)**

```
/plugin marketplace add CSalcedoDataBI/agentic-bi-ops
/plugin install agentic-bi-ops
```
(If `/plugin` UI is unavailable in this harness, document the commands in README and verify the
`.claude-plugin/marketplace.json` parses as valid JSON instead.)

- [ ] **Step 2: Confirm the skills are discoverable**

Expected: `gh-account`, `projects-admin`, and the `/board` command appear in the available skills/commands list.

- [ ] **Step 3: Report** the repo URL, install command, and the verification results to the user.

---

## Self-Review

**Spec coverage:**
- §2 distribution/plugin → Task 1 (manifests) + Task 6 (install). ✓
- §3 gh-account (default CSalcedoDataBI, registry-read, GH_TOKEN per-invocation, scope check, override, 403) → Task 2. ✓
- §4 projects-admin (board/item/automation + conventions + anchoring) → Task 3. ✓
- §5 /board → Task 4. ✓
- §6 error handling/safety (dry-run, target-only writes) → Task 3 Step 1 + Task 5 destructive pattern. ✓
- §7 testing (read-only smoke + throwaway project) → Task 2 Steps 3-4 + Task 5. ✓
- §1 non-goals (no BI yet, no plan→epic dup) → encoded in projects-admin body (Task 3 Step 1). ✓

**Placeholder scan:** `<owner>`/`<repo>`/`<num>` are runtime values resolved at execution, not plan placeholders; all file contents are concrete. ✓

**Type/name consistency:** account keys `csalcedo`/`pal-devs`, vars `GITHUB_TOKEN_PERSONAL`/`GITHUB_TOKEN_BUSINESS`, skill names `gh-account`/`projects-admin`, command `/board` are used identically across tasks. ✓
