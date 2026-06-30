# board-ops — `gh project` Recipes

Concrete commands for creating, configuring, and inspecting a GitHub Projects v2 board. All commands assume `$env:GH_TOKEN` has been set via the `gh-account` skill (Step 0 in SKILL.md).

---

## Create a board and link it to the current repo (coherent `init`)

A board should never be left blank. On **init**, set its identity coherently so the GitHub
Project settings page is not full of empty "Select a repository / short description / README"
placeholders.

```bash
# 1) Create the board under the owner (user or org)
gh project create --owner <owner> --title "<repo> — Roadmap"
# Returns: the new project number (e.g. 3)

# 2) Short description (settings → "Short description")
gh project edit <num> --owner <owner> \
  --description "Roadmap + issue tracking for <owner>/<repo>. Anchored to that repo."

# 3) README (settings → "README")
gh project edit <num> --owner <owner> --readme "# <repo> — Roadmap

Tracks planned work and issues for **<owner>/<repo>**.
Status: Todo / In Progress / Done.
Repo: https://github.com/<owner>/<repo>"

# 4) Link the repo (settings → linked repositories; required before "Default repository")
gh project link <num> --owner <owner> --repo <owner>/<repo>
```

Replace `<owner>` with the GitHub username or org (e.g. `CSalcedoDataBI`) and `<num>` with the
project number returned above. Verify it took:
`gh project view <num> --owner <owner> --format json` → check `shortDescription` and `readme`.

### What `gh` can and cannot do for the settings page
| Settings field | Automatable? | How |
|---|---|---|
| Short description | ✅ | `gh project edit --description` |
| README | ✅ | `gh project edit --readme` |
| Linked repository | ✅ | `gh project link --repo` |
| **Default repository** (pick among linked) | ⚠️ UI only | no `gh`/GraphQL mutation — one click in settings after linking |
| **View name / layout** ("View 1" → Board, group by Status) | ⚠️ UI only | `gh` has no view-management command; rename/group in the UI |

On init, do the four `✅` steps automatically and tell the user the two `⚠️` items are a one-time
UI click (don't claim they were set).

---

## Create fields: Status / Priority / Target as single-select

These three fields are the standard in this ecosystem. Create them once per board.

```bash
# Status field
gh project field-create <num> --owner <owner> \
  --name "Status" \
  --data-type SINGLE_SELECT \
  --single-select-options "Todo,In Progress,Done,Blocked"

# Priority field
gh project field-create <num> --owner <owner> \
  --name "Priority" \
  --data-type SINGLE_SELECT \
  --single-select-options "P0,P1,P2"

# Target field (sprints or milestones — adapt options as needed)
gh project field-create <num> --owner <owner> \
  --name "Target" \
  --data-type SINGLE_SELECT \
  --single-select-options "Sprint 1,Sprint 2,Backlog"
```

---

## List fields (to get field IDs and option IDs)

```bash
gh project field-list <num> --owner <owner> --format json
```

The JSON output includes each field's `id` (node ID, starts with `PVF_`) and each option's `id` (starts with `_`) and `name`. Save these IDs for the set-value step below.

---

## Views and inspection

```bash
# Open the board in the browser
gh project view <num> --owner <owner> --web

# Inspect the project node ID (needed for item-edit)
gh project view <num> --owner <owner> --format json

# List all items currently on the board (JSON — includes item IDs)
gh project item-list <num> --owner <owner> --format json
```

---

## Set a single-select field value on an item

Setting a Status, Priority, or Target value on a board item requires three IDs. Retrieve them first, then call `item-edit`.

### Step 1 — get the project node ID

```bash
# The project node ID is the "id" field (starts with PVT_)
projectId=$(gh project view <num> --owner <owner> --format json --jq .id)
```

### Step 2 — get the field ID and the option ID for the target value

```bash
# List fields with their option IDs
gh project field-list <num> --owner <owner> --format json
# Find the field named "Status" (or "Priority", "Target")
# Under its "options" array, find the option whose "name" matches the value you want (e.g. "Done")
# Copy the field's "id" (fieldId) and the option's "id" (optionId)
```

### Step 3 — get the item ID for the issue/PR you want to update

```bash
# List all items and find the one whose content URL matches your issue
gh project item-list <num> --owner <owner> --format json
# Copy the item's "id" (starts with PVTI_)
```

### Step 4 — set the value

```bash
gh project item-edit \
  --id <itemId> \
  --field-id <fieldId> \
  --project-id <projectId> \
  --single-select-option-id <optionId>
```

All four flags are required. `--project-id` is the node ID (`PVT_…`) from Step 1, not the project number.

---

## Bulk-fill a custom field across EVERY item (by rule)

The "fill all the columns" chore: set one field on every item from a per-item rule — a single-select
by title prefix (e.g. `Categoria`), or a text field by template (e.g. `Ruta` =
`.claude/skills/{name}/SKILL.md`). Use the helper script — it is idempotent, retries transient 502s,
and picks single-select vs text automatically:

```powershell
# single-select by title-prefix map ("*" = fallback):
& "<plugin>/scripts/Set-BoardField.ps1" -Number 6 -Owner PAL-Devs -Field Categoria `
  -PrefixMap '{"apps-":"apps","model-":"model","agent-":"agent","etl-":"etl","viz-":"viz","shared-":"shared","speckit-":"framework","*":"vendored"}'

# text field by template ({title} -> the item's title):
& "<plugin>/scripts/Set-BoardField.ps1" -Number 6 -Owner PAL-Devs -Field Ruta -TextTemplate ".claude/skills/{title}/SKILL.md"

# constant for all matching items:
& "<plugin>/scripts/Set-BoardField.ps1" -Number 6 -Owner PAL-Devs -Field Status -Value Done
```

`-Filter` (regex on the item title) defaults to the skill-name shape `^[a-z0-9]+(-[a-z0-9]+)*$`, so
long-titled tracking issues are skipped; pass your own to widen/narrow the set.

### Gotchas (why a manual loop bites)
- **`cat` is an alias for `Get-Content`** (also `gc`, `sl`, `gi`, …). Naming a helper `Cat`/`function Cat`
  silently runs the alias instead — aliases outrank functions in PowerShell command resolution. Use
  verb-prefixed names (`Resolve-FieldValue`).
- **single-select vs text:** single-select needs `--single-select-option-id <id>`; a text/number field
  needs `--text`/`--number`. Sending `--text` to a single-select (or vice-versa) silently no-ops.
- **Idempotency:** `gh project item-list --format json` surfaces each custom field under a *lowercased,
  stripped* key (`Categoria`→`.categoria`, `Up to Date`→`.uptodate`). Compare against it to skip
  already-set items.
- **Transient 502 Bad Gateway** is common when editing 100+ items back-to-back — retry with backoff
  (the script does 4 tries). Don't treat one 502 as failure.
- **Don't batch via GraphQL in PowerShell** unless you must: escaping the inner `"` of
  `updateProjectV2ItemFieldValue(input:{… value:{singleSelectOptionId:"…"}})` is error-prone
  (`\"` ≠ ``` `" ```). A per-item `item-edit` loop is slower but reliable.

---

## Delete a board (BACKUP FIRST — always)

```bash
# 1) MANDATORY, unconditional backup (do NOT ask) — JSON snapshot + restorable live clone:
powershell -File "${CLAUDE_PLUGIN_ROOT}/scripts/Backup-Board.ps1" -Number <num> -Owner <owner>

# 2) Then confirm with the user (destructive), then delete.
#    gh project delete has NO --yes/-y flag — pipe a confirmation to stdin:
echo "yes" | gh project delete <num> --owner <owner>
```

> ⚠️ Destructive. The backup in step 1 runs **automatically and is never skipped**; only the delete
> needs explicit user confirmation. Verified: the only flags `gh project delete` accepts are
> `--owner/--format/--jq/--template` — there is no skip-confirm flag.

## Visibility (match the repo / showcase)
GitHub Projects are **Private by default**. A board that backs a **public** repo's published
showcase (README/SHOWCASE links to it) must be **Public**, or external visitors hit a wall:
```bash
gh project edit <num> --owner <owner> --visibility PUBLIC    # or PRIVATE
# check: gh project view <num> --owner <owner> --format json --jq .public
```
Rule: never silently flip visibility for a private repo's board; but when a board is linked from a
public repo's docs, set it Public (its items are already public-safe by the same content discipline).

## Get-or-create the board (never duplicate)
Always resolve the existing board before creating one:
```powershell
$num = & "${CLAUDE_PLUGIN_ROOT}/scripts/Resolve-Board.ps1" -Owner <owner> -Repo <owner>/<repo>
```
It reuses the repo's board if it exists (canonical title `<repo> — Roadmap`, or any non-backup board
whose title contains the repo name) and only creates+links+describes a new one if none is found.

---

## Notes

- The project number (`<num>`) is the short integer shown in the board URL and returned by `gh project create`. It is NOT the node ID.
- The node ID (`PVT_…`) is what `gh project item-edit --project-id` expects. Always fetch it with `gh project view <num> --owner <owner> --format json --jq .id` rather than hard-coding it.
- Field option IDs (`_…`) are stable within a board but differ between boards — never copy them across projects.
