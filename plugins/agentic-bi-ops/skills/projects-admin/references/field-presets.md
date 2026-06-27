# field-presets — custom fields, values, and language

Reusable field sets so a board gets coherent governance fields in one step, in the chosen language.
Presets live at `presets/fields.<lang>.json` (`en` default, `es` available). All commands assume
`$env:GH_TOKEN` is set via the `gh-account` skill.

## Apply a preset (idempotent)
```powershell
# from the plugin root; existing fields are skipped, only missing ones are created
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -Lang en
# Spanish governance:
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -Lang es
```

Standard set (EN): **Status, Priority, Type, Area, Estimate, Target**.
Standard set (ES): **Estado, Prioridad, Tipo, Área, Estimado, Objetivo**.

## Create a single custom field by hand
```bash
# single-select with values
gh project field-create <num> --owner <owner> --name "Type" \
  --data-type SINGLE_SELECT --single-select-options "Bug,Feature,Improvement,Chore,Docs,Spike"
# free text / number / date
gh project field-create <num> --owner <owner> --name "Area"     --data-type TEXT
gh project field-create <num> --owner <owner> --name "Estimate" --data-type NUMBER
gh project field-create <num> --owner <owner> --name "Target"   --data-type DATE
```
To SET a single-select value on an item, use the 4-step recipe in `board-ops.md`.

## Language
Pass `-Lang en|es` (default `en`). Presets carry localized field names AND option values. Keep one
language per board for consistency.

## Honest limits (what `gh`/GraphQL cannot do)
| Want | Automatable? | Note |
|------|--------------|------|
| Create fields + option values | ✅ | `field-create` (this file) |
| Apply a whole preset idempotently | ✅ | `Apply-FieldPreset.ps1` |
| **Rename the built-in `Status` field / its options** | ❌ | UI/GraphQL only — the ES preset adds `Estado` as a NEW field instead of renaming `Status` |
| **Which fields are VISIBLE in a view** (show/hide, order) | ❌ | view config is UI/GraphQL-only; do it once in the UI |
| **Group-by / layout (Board vs Table)** | ❌ | UI only |

On apply, do the `✅` rows automatically and tell the user the `❌` rows are a one-time UI step —
never claim a view was configured.
