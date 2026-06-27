---
description: Administer/automate a GitHub Projects board (init/add/move/field/bulk/automate). Defaults to the CSalcedoDataBI account.
---
You are running the agentic-bi-ops /board command.

First apply the `gh-account` skill to set `$env:GH_TOKEN` for the right account (default
CSalcedoDataBI; honor an explicit `--account pal-devs` in the arguments). Never run `gh auth switch`.

Then apply the `projects-admin` skill. Parse the request into ONE of these sub-actions and run the
matching recipe from the projects-admin references:

- **init** — create a board and fill it coherently: title, short description, README, and link the
  repo (references/board-ops.md). Tell the user the two UI-only items (Default repository pick, View
  name/layout) need one click in settings — do not claim they were set.
- **add** — add an issue/PR to the board (references/issue-ops.md)
- **move** — set an item's Status (references/board-ops.md single-select recipe)
- **field** — create fields / apply a field preset (`apply en|es`) / set Status/Priority/Type values
  (references/field-presets.md + board-ops.md). Visibility-per-view and group-by are UI-only — say so.
- **bulk** — batch move/close/label across many items (references/issue-ops.md)
- **automate** — install the actions/add-to-project CI workflow (references/automation.md)

For any destructive action (project delete, bulk close/move), print a dry-run of exactly what
would change and ask the user to confirm BEFORE mutating.

Arguments: $ARGUMENTS
