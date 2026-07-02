# agentic-bi-ops in action — it runs on itself

The best demo of a project-governance tool is the tool governing **its own** project. Everything
below is live data from this repository's own GitHub Projects board — no other project involved.

Every fix here was discovered **while using the tool**, captured (sanitized) through the
`abios-feedback` flow, tracked as an issue on this same board, and shipped. That is the whole idea:
the tool improves itself, in the open.

## The dogfooding loop

```
use the tool  →  hit a rough edge  →  abios-feedback captures it (public-only, sanitized)
      ↑                                              │
      └────────  version bumps  ←  fix lands  ←  it becomes an issue on this board
```

## Live roadmap board

_Snapshot of [agentic-bi-ops — Roadmap](https://github.com/users/CSalcedoDataBI/projects/13).
Regenerate with `scripts/Export-BoardSnapshot.ps1 -Number 13 -Owner CSalcedoDataBI`._

**7 of 10 tracked items done.**

| Status | Item | Issue |
|--------|------|-------|
| In Review | M2 — PBIP / Fabric git ops | [#2](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/2) |
| In Review | M3 — Semantic-model review agents wired to the board | [#3](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/3) |
| In Review | M4 — BI release automation | [#4](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/4) |
| Done | guard: secret patterns self-matched their own definition lines | [#1](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/1) |
| Done | packaging: plugin must live in `plugins/<name>/`, not repo root | [#5](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/5) |
| Done | init: fill board description/README/linked-repo coherently | [#6](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/6) |
| Done | project-scan: exclude noise dirs from scan | [#7](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/7) |
| Done | project-scan: code-marker regex must follow the `TAG:` convention | [#8](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/8) |
| Done | showcase: self-referential example + board snapshot export | [#9](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/9) |
| Done | visibility: public-repo board must be Public | [#10](https://github.com/CSalcedoDataBI/agentic-bi-ops/issues/10) |

The three `In Review` items (M2–M4) are the forward roadmap, their scaffolds open for review;
the `Done` items are self-found improvements — each one a real rough edge the tool surfaced
about itself and then fixed.

## How it evolved

| Version | What shipped |
|---------|--------------|
| 0.1.0 | Foundation: `gh-account` + `projects-admin` + `/board` |
| 0.2.0 | `abios-feedback` + the private-content guard (pre-commit/pre-push) |
| 0.2.1 | Packaging fix — plugin moved to `plugins/<name>/` (issue #5) |
| 0.3.x | Coherent `init` (issue #6) + anti-confusion rules for feedback |
| 0.4.0 | Field presets (EN/ES) + `project-scan` + `/scan` |
| 0.5.0 | Backup-before-delete + resolve-or-reuse board + best-practices |
| 0.5.1 | Scanner noise + false-positive fixes (issues #7, #8) |
| 0.6.0 | Board snapshot export + this showcase |

## Method

Not Scrum — GitHub Projects is **Kanban** at heart (the `Status` flow), with Scrum elements layered
on via fields (`Estimate`, `Target`) — a pragmatic **Scrumban**. Details and sources in
[`plugins/agentic-bi-ops/skills/projects-admin/references/best-practices.md`](plugins/agentic-bi-ops/skills/projects-admin/references/best-practices.md).
