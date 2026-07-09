---
name: skills-bootstrap
description: Use to install curated best-practice skills for authoring and evaluating skills (skill-creator, writing-skills, skill-improver, second-opinion) WITHOUT duplicating what is already installed. Detects the gap against the live inventory, recommends only what is missing, and clean-clones each from its source repo into ~/.claude/skills preserving the LICENSE/attribution. Use when setting up a machine for skill development, or when you want the recommended skill-quality toolkit. NOT for organizing or auditing existing skills — use skills-organize or skills-audit for that. Triggers — "instala las skills de buenas prácticas", "bootstrap skills", "qué skills de calidad me faltan", "setup skill toolkit", /skills bootstrap.
user-invocable: false
---

# skills-bootstrap — the recommended skill toolkit, no duplicates

Part of the **skills-ops** module. Detects gaps, then installs only what is missing —
never re-installing a skill you already have (in any scope).

## Step 1 — Detect the gap (deterministic)

```powershell
$g = & "${CLAUDE_PLUGIN_ROOT}/scripts/Get-SkillGaps.ps1"
$g.summary
"Installed:"; $g.installed | Select-Object name,purpose | Format-Table
"Gaps:";      $g.gaps      | Select-Object name,repo,license,purpose | Format-Table
```

The catalog is `presets/recommended-skills.json`. A recommended skill counts as installed
if its `name` appears anywhere in the inventory (plugin / personal / project) — so
`anthropic-skills:skill-creator` already covers `skill-creator`, and nothing is duplicated.

## Step 2 — Install only the gaps (clean clone, license preserved)

For each gap, confirm with the user, then:

```powershell
& "${CLAUDE_PLUGIN_ROOT}/scripts/Install-SkillFromRepo.ps1" `
    -Repo <owner/name> -Path <subpath> -Name <skill-name>
```

It shallow-clones to a temp dir, copies only that skill folder into `~/.claude/skills/<name>`,
copies the source `LICENSE` next to it (mandatory for CC BY-SA sources), and cleans up. It
**skips** an already-present skill unless `-Force`.

## Step 3 — Verify

Re-run `Get-SkillGaps.ps1` — `summary.gaps` should drop. Restart the session so the new
skills' descriptions load. Report what was installed, from where, and under which license.

## Rules
- Never install a skill that already exists in any scope (Step 1 enforces this).
- Always preserve the upstream LICENSE/attribution — especially CC BY-SA.
- General-purpose skills go to the global `~/.claude/skills/`; project-specific ones go to the
  repo's `.claude/skills/` instead.
