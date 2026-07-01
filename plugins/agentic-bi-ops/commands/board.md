---
description: Administer/automate a GitHub Projects board (init/add/move/field/bulk/fill/automate). Defaults to the CSalcedoDataBI account.
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
- **field** — create fields / apply a field preset (`apply en|es`) / set Status/Priority/Type values /
  **bulk-fill any custom field across EVERY item by rule** (`scripts/Set-BoardField.ps1` — single-select
  by title-prefix map, or text by `{title}` template — idempotent, retries 502s)
  (references/field-presets.md + board-ops.md). Visibility-per-view and group-by are UI-only — say so.
- **bulk** — batch move/close/label across many items (references/issue-ops.md)
- **fill** — detect and fill column gaps across all board items (projects-admin skill — /board fill section):
  - No flags: read all items via GraphQL, print a plan of every gap found (missing assignee, wrong
    Status), then ask the user for confirmation before making any change.
  - `--dry-run`: print the plan only, execute nothing.
  - `--auto`: fill without asking — assign owner if empty, sync Status from issue/PR state — same
    logic as `bash scripts/board-sync.sh`. Use for CI or when the user has already approved.
  - NOTE: Linked PRs and Sub-issues progress are system-derived columns — GitHub sets them
    automatically from PR mentions and sub-issue state. They are NOT writable via API; do not
    attempt to fill them and explain this to the user if asked.
- **automate** — install the actions/add-to-project CI workflow (references/automation.md)

SAFETY (mandatory, see references/best-practices.md):
- Before init/add/plan, **resolve-or-reuse** the repo's board with `scripts/Resolve-Board.ps1` —
  never create a duplicate board with a blind `gh project create`.
- Before ANY board delete, **always run `scripts/Backup-Board.ps1` first** (JSON snapshot + live
  clone) — unconditionally, without asking. The delete itself still needs explicit confirmation.
- For any destructive action (delete, bulk close/move), print a dry-run of exactly what would
  change and confirm BEFORE mutating.

Arguments: $ARGUMENTS