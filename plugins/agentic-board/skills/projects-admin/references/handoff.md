# /board handoff — resume work across sessions (design + reference)

**Status:** spec (epic #137, issues #138–#144) · **Date:** 2026-07-07

The `/board handoff` sub-action lets a user stop mid-task and resume it in a **fresh session days
later — even on another machine** — without re-typing the context.

- **save** — write a *curated, verified* snapshot of "the last important thing + the concrete next
  step + open traps", linked to the board issue/PR/branch of the active `/board work` session.
- **resume** — read the latest snapshot back, rehydrate context, carry forward unresolved traps,
  and offer to continue (`/board work -Start` the linked issue).

## Grounding (build-vs-reuse, researched 2026-07-07)

Native Claude Code already covers most of the mechanism, so we **reuse, not reinvent**:

- `/resume` / `--continue` restore the full transcript and persist across days — but they are
  **machine-local** and reload the whole noisy history (uncurated).
- **SessionStart hook** can inject `additionalContext` on `source: resume` → the auto-load hook (#142).
- **Auto-memory** (`MEMORY.md`) persists across days but is machine-local and fact-oriented, not task-state.
- Checkpoints (Esc-Esc) are intra-session only → irrelevant.

**The gap** none fills: a curated, portable, board-linked "where I was + next step + traps". We
build that thin layer. Reference patterns borrowed (NOT depended on):

| Reference | License | What we take |
|-----------|---------|--------------|
| Cline Memory Bank | Apache-2.0 | Minimal file set idea (`activeContext` + `progress`), not all six files |
| ostikwhy-blip/claude-code-handoff-skill | MIT | `[V]`/`[?]` verification tagging, CREATE vs RESUME mode, archiving, degradation detection |
| Serena `.serena/memories/*.md` | MIT | Write-on-demand model |

Heavy semantic memory (mem0/Letta/MCP memory server) is the **wrong shape** and is rejected. The
only *installable* heavy option, **Basic Memory** (AGPL-3.0), is offered via suggest-and-install
only, under the security rules in #143 — never vendored.

## Architecture

`/board handoff` is a **sub-action of the existing `/board` command** (menu option 16), backed by
one script following the `Board-*.ps1` convention. It reuses the board as the durable store.

| Unit | Kind | Responsibility |
|------|------|----------------|
| `Board-Handoff.ps1` | script | `-Save` / `-Resume`; autofill from `sessions.json`; post/read the board comment; write/read the local mirror |
| `/board handoff` | sub-action | Menu entry + CREATE/RESUME detection + the verified-save protocol (agentic) |
| SessionStart hook | hook (#142, opt-in) | On `source: resume`, inject a one-line pointer to the latest handoff via `additionalContext` |

### Persistence model (key decision)

The durable **source of truth is a pinned comment on the linked board issue**, fenced and tagged
`[abios-handoff]`. Rationale — it is **cross-machine and cross-day**, survives branch deletion after
merge, needs no git-branch coupling, and adds **no noise to `main`**; it reuses the board we already
have as the persistence layer.

- **Board-linked session** (started via `/board work`): `save` upserts the `[abios-handoff]` comment
  on the issue **and** writes a local mirror `HANDOFF.md` at repo root (gitignored). `resume` reads
  the latest `[abios-handoff]` comment (works from a clean checkout on machine B), regenerating the
  local mirror.
- **No board link** (ad-hoc work): fall back to a local `HANDOFF.md` only; `save` suggests committing
  it (or `--commit`) so it travels, since there is no issue to hold it.
- Previous snapshots rotate to `.handoffs/<yyyyMMddTHHmmssZ>-handoff.md` (gitignored local history) —
  a **colon-free** basic-format ISO-8601 UTC timestamp, since `:` is invalid in Windows filenames and
  this is a PowerShell feature. The issue comment keeps only the latest; the edit history of the
  comment is the remote history.

`HANDOFF.md` and `.handoffs/` are added to the repo `.gitignore` by `save` (idempotent); the board
comment — not a committed file — is what makes it portable. (Note: this repo already gitignores
`/docs/`, so design specs like this one live under the tracked skill `references/` instead.)

## HANDOFF.md format

YAML frontmatter (machine-read autofill) + human sections. Every factual claim carries a
verification tag (see protocol below).

```markdown
---
issue: 138
repo: CSalcedoDataBI/agentic-board
branch: issue-138-design-handoff-md-schema-verification
pr: 145            # null when no PR yet
board: 13
saved: 2026-07-07T14:32:00Z   # RFC3339 UTC (always Z) — unambiguous cross-machine
host: DESKTOP-XYZ
verified: 8/10     # [V] claims / total claims
---

# Handoff — #138 Design HANDOFF.md schema

## Next concrete step
[V] Implement Board-Handoff.ps1 -Save: start with the frontmatter writer (section "HANDOFF.md format").

## Done this session
- [V] Wrote references/handoff.md spec (commit <sha>)
- [V] Updated issue #143 with the security checklist

## Open threads / decisions pending
- [?] Whether `.handoffs/` archive should ever be committed (leaning: no, gitignored)

## Traps / failed approaches (do NOT repeat)
- [V] `gh search repos --json licenseInfo` is invalid — the field is `license`
- [V] This repo gitignores `/docs/` — spec/plan docs there are never committed; put tracked docs under skill `references/`

## Key files
- plugins/agentic-board/skills/projects-admin/references/handoff.md
- plugins/agentic-board/scripts/Board-Work.ps1 (sessions.json schema, ~L206)
```

Frontmatter autofill maps directly from the `sessions.json` entry written by `Board-Work.ps1`
(`issue`, `repo`, `branch`, `workPath`, `host`) plus the PR resolved from the branch with the
repo-consistent form `gh pr list --repo <repo> --head <branch> --state open --json number`
(the repo's other `gh pr view` calls take a PR *number* + `--repo`, never a positional branch),
and the board number from the resolved board. `saved` is stamped as RFC3339 UTC (`...Z`).

## Verification protocol ([V] / [?])

The handoff is written precisely when context is degraded, so it must not launder guesses as facts.
On `save`, the routine **actively re-runs** the checks and tags each claim:

- `[V]` **verified** — confirmed by a command or file read *during this save run*:
  `git status --porcelain`, `git log --oneline -5`, `git branch --show-current`,
  `gh pr list --head <branch> --state open --json number`, reading a named file, or running the
  project's test command.
- `[?]` **unverified** — recalled from session memory, not re-checked this run.

The frontmatter `verified: N/M` ratio surfaces how much of the handoff is grounded. `resume`
re-verifies `[V]` items are still true (branch exists, PR still open) and flags drift.

## CREATE vs RESUME detection

- Explicit `save` / `resume` always win.
- Bare `/board handoff`: if a `[abios-handoff]` comment exists on the current issue (or a local
  `HANDOFF.md` exists) **and** the session is fresh (little work done) → **RESUME** (show it, ask to
  continue). Otherwise → **SAVE** (offer to snapshot).
- **Degradation nudge** (Phase 2, borrowed from the ostikwhy pattern): if mid-session the agent
  notices it contradicted itself or re-explored settled ground, it may proactively offer
  `/board handoff save`, then stop for confirmation — never auto-saves.

## Capture-in-handoff (knowledge anti-rot)

The knowledge registry (M5) rots if it depends on the user remembering to feed it. So `save`
closes the loop: after writing the handoff, it proposes the **knowledge references touched this
session** that are not yet catalogued —

- every `http(s)` URL mentioned in the narrative (Next step / Done / Open threads / Traps), and
- **doc-like** key files that exist on disk (a `.md` or a folder — code files are skipped),
  normalized to repo-relative forward-slash refs,

deduped against `knowledge/registry.json`. It only **proposes** ready-to-run `/knowledge add`
lines — it never auto-adds (the "never invent references" rule); the skill asks which to keep and
the user picks a domain for each. Best-effort: a missing or unreadable registry never fails the
save. Opt out with `-NoKnowledge`. This reuses the existing session-close flow so references get
captured at the exact moment they are still fresh, instead of being re-found later.

## Security

- The suggest-and-install of Basic Memory is gated by the full checklist in #143 (pinned version,
  provenance, human gate, update-review, reversible uninstall) and the hard rule: **never
  vendor/fork AGPL code into this repo** — install from upstream, talk over MCP only.
- The handoff writes to the **current repo's board only** (resolved via the session `repo`), so a
  private project's context never lands on the tool's board.

## Testing

Pester 5 over the pure helpers: frontmatter parse/serialize round-trip, `sessions.json` →
frontmatter autofill mapping, `[V]`/`[?]` tag counting for the `verified` ratio, CREATE vs RESUME
detection given (comment present?, session freshness), and `.gitignore` idempotency. The
verified-save re-run and the resume rehydration are agentic (driven by the sub-action prose).

## Task map

| Issue | Delivers |
|-------|----------|
| #138 | This spec |
| #139 | `Board-Handoff.ps1 -Save` (verified snapshot, comment upsert, local mirror, archive) |
| #140 | `Board-Handoff.ps1 -Resume` (read latest, rehydrate, carry traps, offer start) |
| #141 | Autofill from `sessions.json` + a `project` memo pointer in `MEMORY.md` |
| #142 | SessionStart auto-load hook (opt-in) |
| #143 | Suggest-and-install Basic Memory (security-gated) |
| #144 | Docs (`/board` menu option 16, README) + Pester tests + upstream attribution |

## Deferred

- Proactive degradation nudge (Phase 2).
- `--commit` mode to version `HANDOFF.md` in-repo for ad-hoc (non-board) work.

## Attribution

This module **borrows design patterns** from prior art; it does **not** copy or vendor any of
their code (all implementation here is original PowerShell, MIT like the rest of the plugin):

- **Cline Memory Bank** (Apache-2.0) — the minimal committed-Markdown memory convention
  (`activeContext` / `progress`). We took the *idea* of a small, human-readable, always-read file
  set. <https://docs.cline.bot/prompting/cline-memory-bank>
- **ostikwhy-blip/claude-code-handoff-skill** (MIT) — the `[V]`/`[?]` verification tagging, the
  CREATE-vs-RESUME mode selection, and the archive-previous-handoff idea.
  <https://github.com/ostikwhy-blip/claude-code-handoff-skill>
- **Serena** (MIT) — the write-on-demand filesystem-memory model.
- **Basic Memory** (AGPL-3.0) — suggested-and-installed from upstream for the heavy case only,
  never vendored (see `heavy-memory.md`).
