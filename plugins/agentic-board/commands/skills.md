---
description: Manage the Agent Skills lifecycle — organize/catalog, audit for failures, or bootstrap best-practice skills. Part of the skills-ops module.
---
You are running the agentic-board /skills command.

**If $ARGUMENTS is empty or only whitespace, do NOT run anything yet.** Show this menu and wait
for the user to pick (they can answer with just the number):

```
¿Qué quieres hacer con tus skills?

1. organize   → catálogo + salud de tus skills (lint, near-duplicates, misplaced) y, si quieres,
                reorganizar un repo/monorepo a .claude/skills/<proyecto>/<skill>/ sin mezclar
2. audit      → detectar skills que fallan (descripción, triggers, solapes) + eval de triggering,
                y abrir un issue SANEADO en el repo dueño de la skill (jamás en tu proyecto privado)
3. bootstrap  → instalar las skills de buenas prácticas que te falten (skill-creator, writing-skills,
                skill-improver, second-opinion) sin duplicar lo que ya tienes
```

When they answer (number or name), invoke the matching skill and follow it:

- **organize** → the `skills-organize` skill. Report mode is read-only (catalog + health via
  `Get-SkillInventory.ps1`); reorganize mode is propose→confirm→`git mv` via
  `Move-SkillsLayout.ps1` (dry-run first, clean git tree required, exact revert printed). Only
  touches project skills inside the target repo — never the plugin cache or `~/.claude/skills`.
- **audit** → the `skills-audit` skill. Static audit via `Invoke-SkillAudit.ps1` (routed to each
  skill's OWNER repo by `Resolve-SkillOwner.ps1`), plus the on-demand runtime trigger-eval
  (enabled-vs-disabled, 3×). Filing is SANITIZED and behind a human gate — the tool's own board
  for its skills, the project's board for the project's own skills, local-only for third-party.
  Reuses `gh-account`, the `abios-feedback` discipline, and the `guard-no-private.ps1` backstop.
- **bootstrap** → the `skills-bootstrap` skill. `Get-SkillGaps.ps1` finds missing recommended
  skills (never duplicating an installed one); `Install-SkillFromRepo.ps1` clean-clones each gap
  into `~/.claude/skills` preserving the source LICENSE.

Identity: any operation that files an issue must first set `$env:GH_TOKEN` via the `gh-account`
skill (default CSalcedoDataBI). Read-only report/audit needs no token.

Arguments: $ARGUMENTS
