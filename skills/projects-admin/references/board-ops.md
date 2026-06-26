# board-ops — `gh project` Recipes

Concrete commands for creating, configuring, and inspecting a GitHub Projects v2 board. All commands assume `$env:GH_TOKEN` has been set via the `gh-account` skill (Step 0 in SKILL.md).

---

## Create a board and link it to the current repo

```bash
# Create the board under the owner (user or org)
gh project create --owner <owner> --title "<repo> — Board"
# Returns: the new project number (e.g. 3)

# Link the board to a single repo (run inside the repo working directory)
gh project link <num> --owner <owner> --repo <owner>/<repo>
```

Replace `<owner>` with the GitHub username or org (e.g. `CSalcedoDataBI`) and `<num>` with the project number returned above.

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

## Notes

- The project number (`<num>`) is the short integer shown in the board URL and returned by `gh project create`. It is NOT the node ID.
- The node ID (`PVT_…`) is what `gh project item-edit --project-id` expects. Always fetch it with `gh project view <num> --owner <owner> --format json --jq .id` rather than hard-coding it.
- Field option IDs (`_…`) are stable within a board but differ between boards — never copy them across projects.
