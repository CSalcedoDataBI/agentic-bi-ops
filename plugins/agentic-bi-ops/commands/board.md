---
description: Administer/automate a GitHub Projects board (init/add/move/field/bulk/automate). Defaults to the CSalcedoDataBI account.
---
You are running the agentic-bi-ops /board command.

First apply the `gh-account` skill to set `$env:GH_TOKEN` for the right account (default
CSalcedoDataBI; honor an explicit `--account pal-devs` in the arguments). Never run `gh auth switch`.

Then apply the `projects-admin` skill. Parse the request into ONE of these sub-actions and run the
matching recipe from the projects-admin references:

- **init** — create a board and link it to the current repo (references/board-ops.md)
- **add** — add an issue/PR to the board (references/issue-ops.md)
- **move** — set an item's Status (references/board-ops.md single-select recipe)
- **field** — create or set Priority/Target/Status values (references/board-ops.md)
- **bulk** — batch move/close/label across many items (references/issue-ops.md)
- **automate** — install the actions/add-to-project CI workflow (references/automation.md)

For any destructive action (project delete, bulk close/move), print a dry-run of exactly what
would change and ask the user to confirm BEFORE mutating.

Arguments: $ARGUMENTS
