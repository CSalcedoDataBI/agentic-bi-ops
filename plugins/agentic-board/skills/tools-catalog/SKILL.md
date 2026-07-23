---
name: tools-catalog
description: Use to browse, research and install the project's referenced external tools from one unified catalog that merges the knowledge registry (references) with the installable toolkit presets. Install one tool or all missing installables at once, kind-aware (skill-clone preserves LICENSE; a plugin surfaces its own install command, never cherry-picked). The discoverability surface at the intersection of knowledge-ops and skills-ops. Triggers — "/tools", "navega las herramientas referenciadas", "instala esta herramienta", "instálalas todas", "qué herramientas hay para instalar".
user-invocable: false
---

# tools-catalog — unified referenced-tools catalog (browse · research · install)

The single browsable surface for the external tools this project *references* and can *install*.
It merges two sources that until now lived apart:

- **References** — `knowledge/registry.json` (the knowledge-ops registry): every catalogued
  URL / repo / doc, by domain. This is *what exists and why* — not necessarily installable.
- **Installers** — `presets/toolkits/*.json` (the skills-ops toolkit presets, e.g. `bi.json`,
  `quality.json`): the curated tools that carry an install method. This is *what can be installed*.

A tool can appear in one source or both. The catalog is their union, de-duplicated, each item
carrying: `name, domain, kind, url, installable, install-method, installed`.

> **Scope (M3 ∩ M5).** This surface REFERENCES / INSTALLS / MONITORS external tools — it never
> rebuilds them. It reuses the existing engines (`Get-SkillGaps.ps1` for installed-detection,
> `Install-SkillFromRepo.ps1` for skill-clone); it does not reimplement install or gap logic.

## Sub-actions

### browse  (read-only, no token)
Run `scripts/Show-ToolsCatalog.ps1` — it renders the unified catalog grouped by domain, each row
showing `[installed|available|reference]`, the id, the kind, and the URL. It reads
`scripts/Get-ToolsCatalog.ps1` under the hood (registry + presets merged, installed-state via the
`Get-SkillGaps` rules); pass `-Json` to the resolver directly when you need the raw item model.

### research <id>  (read-only)
Run `scripts/Show-ToolsCatalog.ps1 -Id <id>` — it surfaces ONE tool's name, source, URL, install
method and note so the user reads the reference before deciding. `<id>` matches the row id or the
tool name (case-insensitive). Never installs anything.

### install <id>  (confirm each; never duplicate)
Install one item by KIND:
- `skill-clone` → `scripts/Install-SkillFromRepo.ps1` (clean `--depth 1` clone, copy only the skill
  folder, **preserve LICENSE**). Skipped with a note when `Get-SkillGaps.ps1` already shows it installed.
- `plugin` (e.g. `microsoft/skills-for-fabric`) → all-or-nothing: SURFACE its own install command,
  never cherry-pick a single skill out of it.

The hardened selective-install path is delivered in #387.

### install --all  (one pass, one confirmation)
Batch-install every MISSING installable in a single dry-run-then-confirm pass. Plugin-kind entries
are listed SEPARATELY (surfaced, not installed blindly). Delivered in #388.

## Identity
`browse` and `research` need no token. An install that clones or files follows the `gh-account`
discipline (default CSalcedoDataBI) like the rest of the suite.

## Not this
- Managing the references themselves (add / harvest / wiki) → the `knowledge-registry` skill.
- Installing a whole profile toolkit without the catalog UI → the `skills-bootstrap` skill.
- Auditing installed skills' health → `skills-organize` / `skills-audit`.
