# field-presets — custom fields, values, and language

Reusable field sets so a board gets coherent governance fields in one step, in the chosen language.
Presets live at `presets/fields.<lang>.json` (`en` default, `es` available). All commands assume
`$env:GH_TOKEN` is set via the `gh-account` skill.

## Apply a preset (idempotent, standardizes by default)
```powershell
# from the plugin root; existing fields are skipped, only missing ones are created,
# and legacy option names (Todo, P2 Medium, …) are renamed onto the canonical ones
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -Lang en
# Spanish governance:
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -Lang es
```

Standard set (EN): **Status, Priority, Size, Type, Area, Estimate, Target**.
Standard set (ES): **Estado, Prioridad, Tamaño, Tipo, Área, Estimado, Objetivo**.

A rename touches every item assigned to the option at once, so the plan is **printed and confirmed**
first. Answering `n` skips the standardizing and applies the rest of the preset.

```powershell
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -DryRun  # preview
& "${CLAUDE_PLUGIN_ROOT}/scripts/Apply-FieldPreset.ps1" -Number <num> -Owner <owner> -Yes     # CI / pre-approved
```

## Standardizing a board born from GitHub's template

A template board (`Status: Todo / In Progress / Done`) is migrated onto the canonical vocabulary by
the plain apply above — no flag needed. The legacy option is **renamed in place**, never duplicated.

This was opt-in behind `-Migrate` until issue #300, and that default was the bug: the documented
command matched options by name only, so it added `Backlog` *next to* `Todo`, every item stayed on
`Todo`, and the board ended up with two options meaning the same thing — the one state a rename can
never repair (GitHub forbids two options with the same name). `-Migrate` is still accepted as a no-op.

To opt out, `-NoMigrate` leaves the legacy names alone. Opting out does **not** re-create the old
behavior: the canonical option is simply not created beside the legacy one. There is no longer any
path through this script that produces a duplicate.

The rename is sent with the option's **existing id** and the canonical name, so **every item keeps its
assignment** — no bulk item rewrite, no orphans. The legacy→canonical map lives in
`scripts/Get-BoardVocabulary.ps1` (`Todo`→`Backlog`, `P2 Medium`→`P2`, …); an option name that is not
in it is left alone rather than guessed. Idempotent: on an already-canonical board it plans nothing.

Verified on a scratch board created from GitHub's default template: `Todo`→`Backlog` renamed, the item
sitting on `Todo` read `Backlog` afterwards, and Status ended with exactly the 5 canonical options.

**Conflict:** if the board has BOTH `Todo` and `Backlog` (what a pre-#300 plain apply left behind),
the rename is **skipped and reported** — GitHub rejects two options with the same name. This no longer
needs the UI: run `Apply-FieldPreset.ps1 -MergeConflicts` (preview with `-DryRun`). It moves every item
off the legacy option onto the canonical one **by id**, verifies the move, and only then deletes the
legacy option. Because it deletes an option it stays opt-in on its own flag — a plain apply reports the
conflict and points you here rather than destroying anything unasked.

> **Never resolve this by re-sending `singleSelectOptions` by NAME.** `updateProjectV2Field` with names
> and no ids makes GitHub recreate every option with fresh ids, orphaning all item assignments — every
> item loses its Status at once, silently, and the next apply still reports success. `-MergeConflicts`
> avoids it by moving items first (by id) and re-sending the survivors by id; that ordering is the whole
> point. A board created through `Resolve-Board.ps1` never reaches this state — it is born on the
> canonical vocabulary (#299), so the conflict only exists on boards made before that.

Everything below `Status`/`Priority`/`Size` is out of the vocabulary's scope — the ES preset's `Estado`
is a different FIELD, so `-Migrate` does not touch ES boards.

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
| Rename a single-select field's **options** (e.g. `Todo`→`Backlog`) | ✅ | `Apply-FieldPreset.ps1` (default) — `updateProjectV2Field` with the option's existing id; item assignments survive |
| **Merge** a `Todo`+`Backlog` duplicate (move items, delete the spare) | ✅ | `Apply-FieldPreset.ps1 -MergeConflicts` — moves items by id, verifies, then deletes the legacy option (opt-in; it deletes an option) |
| **Rename the built-in `Status` FIELD itself** | ❌ | UI only — the ES preset adds `Estado` as a NEW field instead of renaming `Status` |
| **Which fields are VISIBLE in a view** (show/hide, order) | ❌ | view config is UI/GraphQL-only; do it once in the UI |
| **Group-by / layout (Board vs Table)** | ❌ | UI only |

On apply, do the `✅` rows automatically and tell the user the `❌` rows are a one-time UI step —
never claim a view was configured.
