---
description: Administer/automate a GitHub Projects board (init/add/move/field/bulk/fill/automate). Defaults to the CSalcedoDataBI account.
---
You are running the agentic-bi-ops /board command.

**If $ARGUMENTS is empty or only whitespace, do NOT run anything yet.** Show this menu and wait
for the user to pick (they can answer with just the number):

```
¿Qué quieres hacer con el board?

1. fill --dry-run   → ver qué gaps hay (assignees, Status, Priority, Size, Type) SIN cambiar nada
2. fill --auto      → llenar todos los gaps automáticamente (convierte drafts a issues reales)
3. fill             → llenar gaps pidiendo confirmación antes de ejecutar
4. init             → crear/configurar el board de este repo
5. add <url>        → añadir un issue/PR al board
6. move             → cambiar el Status de un item
7. field            → crear campos o llenar un campo en todos los items por regla
8. bulk             → mover/cerrar/etiquetar muchos items a la vez
9. automate         → instalar CI que sincroniza el board solo
```

When they answer (number or name), execute that sub-action following the instructions below.

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
- **fill** — detect and fill ALL gaps across the board by running `scripts/Board-Fill.ps1`
  (pass -Owner, -Repo, -ProjectNum for the current repo's board):
  - The script converts any draft notes to REAL issues in the repo first, then fills gaps:
    Assignees (owner), Status (from issue/PR state), Priority (P2 Medium), Size (M),
    Type (from labels, else Feature).
  - No flags: run with neither -DryRun nor -Auto — the script prints the plan and asks (s/n).
  - `--dry-run`: run with -DryRun — plan only, executes nothing.
  - `--auto`: run with -Auto — fills everything without asking. Use for CI or when already approved.
  - NOTE: Linked PRs and Sub-issues progress are system-derived columns — GitHub sets them
    automatically from PR mentions and sub-issue state. They are NOT writable via API; do not
    attempt to fill them and explain this to the user if asked.
  - NOTE: which columns a VIEW displays is UI-only — if fields look "empty" on the board page,
    tell the user to click `+` at the right of the view header and enable Priority/Size/Type.
- **automate** — install the actions/add-to-project CI workflow (references/automation.md)

ALWAYS END WITH THE BOARD LINK (mandatory): every response about a board operation — plan,
result, or error — must end with the board URL so the user can open it in one click:
`https://github.com/users/<owner>/projects/<num>` (or `/orgs/<org>/projects/<num>` for org boards).

SAFETY (mandatory, see references/best-practices.md):
- Before init/add/plan, **resolve-or-reuse** the repo's board with `scripts/Resolve-Board.ps1` —
  never create a duplicate board with a blind `gh project create`.
- Before ANY board delete, **always run `scripts/Backup-Board.ps1` first** (JSON snapshot + live
  clone) — unconditionally, without asking. The delete itself still needs explicit confirmation.
- For any destructive action (delete, bulk close/move), print a dry-run of exactly what would
  change and confirm BEFORE mutating.

Arguments: $ARGUMENTS
