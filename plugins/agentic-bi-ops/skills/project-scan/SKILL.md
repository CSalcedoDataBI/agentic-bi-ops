---
name: project-scan
description: Use to scan the CURRENT project for latent, hard-to-track work — code TODO/FIXME, unchecked checklists and "pending/next steps" in docs, and plan/spec docs not yet tracked — then convert the chosen items into issues + a work plan on THIS project's board. Triggers — "escanea el proyecto", "convierte los pendientes en issues", "harvest backlog", "qué hay sin trackear", "arma el plan de trabajo", /scan.
---

# project-scan — turn latent work into tracked issues/plan

## What it is (and is NOT)
Surfaces work that already exists in the repo but isn't tracked, and turns the items you pick into
issues on a board. **This targets the CURRENT project** — the opposite of `abios-feedback` (which
targets the tool's own repo). Do not confuse them.

## Identity & target (anti-confusion)
1. **Target = the CURRENT repo.** Resolve it: `gh repo view --json nameWithOwner -q .nameWithOwner`.
   Issues are created ONLY there.
2. **Account matches that repo's owner**, via [[gh-account]]: a personal repo → `GITHUB_TOKEN_PERSONAL`;
   a `PAL-Devs` (org) repo → `--account pal-devs` (`GITHUB_TOKEN_BUSINESS`). If you get a 403, switch.
3. Never invent issues in another repo or the tool's repo.

## Step 1 — Scan (default sources)
Run these read-only scans (ripgrep / the Grep tool), excluding vendored/build dirs:

```bash
# a) code debt markers
rg -n --no-heading -e '\b(TODO|FIXME|HACK|XXX|BUG)\b' \
   -g '!**/{node_modules,dist,build,.git,vendor,Tables,outputs}/**'

# b) unchecked checklist items + pending sections in docs
rg -n --no-heading -e '^\s*[-*] \[ \] ' -g '*.md'
rg -n --no-heading -i -e '^\s*#{1,6}\s*(pendiente|pendientes|todo|next steps|por hacer)\b' -g '*.md'

# c) plan/spec docs (candidates that may not be tracked yet)
rg -l --files -g 'docs/**/plans/**.md' -g 'specs/**.md' -g '.claude/plans/**.md' 2>/dev/null
```
Optional extras when asked: `CHANGELOG` "Unreleased" sections, tests marked `skip`/`todo`/`xfail`.

For (c), a plan is "already tracked" if an open issue references its path/title. Check with
`gh issue list --repo <owner>/<repo> --search "<plan title>"` before proposing it.

## Step 2 — Normalize & dedupe
For each finding produce: `{title, type, file:line, evidence}`. Map to a **Type**:
- TODO/FIXME/HACK/XXX → Type=Chore or Bug (judge by wording)
- checklist/pending → Type=Feature/Chore
- plan/spec → Type=Spike/Feature (usually an epic)
Drop duplicates (same file+line, or a finding already matching an open issue title).

## Step 3 — Propose, then confirm (NEVER auto-create)
Print a table the user can edit before anything is created:

| # | Title | Type | Source |
|---|-------|------|--------|
| 1 | … | Bug | src/x.ts:42 |

Ask which rows to create (all / a subset / none). Only after explicit confirmation, proceed.

## Step 4 — Create issues + assemble the plan on the board
```bash
# label per type (idempotent)
gh label create scan --color BFD4F2 --force --repo <owner>/<repo>
# create each confirmed issue in the CURRENT repo
url=$(gh issue create --repo <owner>/<repo> --label scan --title "<title>" \
        --body "Source: <file:line>\n\n<evidence>\n\nHarvested by project-scan.")
# ensure a board exists (see projects-admin board-ops "coherent init"), then add it
gh project item-add <num> --owner <owner> --url "$url"
```
Optionally apply governance fields first with the field preset (see `../projects-admin/references/field-presets.md`)
and set **Type/Status** per item (single-select recipe in `board-ops.md`). For a set of plan/spec
docs, create one epic issue and link the rest as sub-issues (see `issue-ops.md`).

## Safety
- Read-only scan first; **dry-run table + confirmation** before creating anything.
- Issues only in the resolved origin repo; honor the account/scope rules.
- Keep each issue body factual (file:line + evidence); don't paste large secret-bearing snippets —
  the same private-content discipline applies if the repo is public.
