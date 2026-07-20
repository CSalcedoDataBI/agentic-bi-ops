# bi-release-checklist — release spec for BI artifacts (M4.1)

The definition of "ready to release" for a **BI artifact** — a Power BI report (PBIR), a semantic
model (TMDL), or the PBIP project that carries both — plus the Fabric items built on them. It is the
checklist a team runs before promoting a model/report to a shared workspace, and the spec the tool's
release automation is built around (M4: changelog + review gate).

**Scope, honestly.** This tool GOVERNS the release (the board, the review gate, the changelog) and
REFERENCES the Fabric/Power BI ecosystem that actually deploys the artifact — it does not rebuild
deployment pipelines or refresh orchestration (that is Fabric's job; see the M3 toolkit-provisioning
stance). Every item below is marked **[tool]** (an agentic-board command runs or enforces it),
**[external]** (a Fabric/PBI/CI capability the tool points at but does not own), or **[manual]** (a
human judgement the tool surfaces but never makes).

## Definition of done — a BI artifact is releasable when…

### 1. Model & report quality
- **[tool] BPA clean at error severity.** The semantic model passes Tabular Editor's Best Practice
  Analyzer with no `error`-severity violations. Enforced in the review gate:
  `Bpa-GateReview.ps1 -FailOn error` (run automatically by `Board-ReviewGate.ps1` when the PR touches
  `*.tmdl`). A committed `BPARules.json` (or `ABIOS_BPA_RULES`) defines the bar; without one the check
  skips (it never blocks on the *absence* of rules). Author rules with the `tabular-editor:bpa-rules`
  skill (`/skills bootstrap bi`).
- **[tool] No unreviewed breaking schema change.** `Tmdl-DiffReview.ps1 -FailOnBreaking` (also in the
  gate) blocks a merge that drops a column, changes a data type, or deletes a measure/table until the
  change is acknowledged. A breaking change is often intentional (dropping a deprecated column) — the
  gate forces the acknowledgement, it does not forbid the change.
- **[manual] Report renders.** Pages open, visuals bind, no broken field references after the model
  change. The tool cannot see a rendered report — a human (or a downstream Fabric CI job) confirms it.

### 2. Change review
- **[tool] Merged through the review gate, not direct to the default branch.** `Board-ReviewGate.ps1`
  → `Board-Merge.ps1`. The gate requires green CI, no `CHANGES_REQUESTED`, no unresolved threads, and
  (§1) no TMDL-breaking / BPA-error findings.
- **[tool] Right-sized PR.** The gate warns past 600 lines / 20 files; a large model change is split
  with `Board-Breakdown.ps1` so it can actually be reviewed.
- **[external] A reviewer other than the author.** Copilot code review when available, else an
  explicit self-review of `gh pr diff` (the gate mandates one when no reviewer arrives).

### 3. Versioning & changelog
- **[manual] The artifact carries a version.** Semantic-version the model/report (or tag the release)
  so a consumer can tell two builds apart. BI artifact versioning lives in the artifact's own metadata
  / a git tag — the tool does not stamp it (it only versions its own plugin, via `New-Release.ps1`).
- **[tool] Changelog entry generated from the board.** `/board changelog` (`Board-Changelog.ps1`)
  turns the Done issues into an Added/Changed/Fixed block, deduped against what is already cited, and
  folded into `CHANGELOG.md` — composing with a hand-written `[Unreleased]` block (#324).

### 4. Deployment & promotion
- **[external] Promoted through the deployment pipeline, not edited in prod.** Fabric deployment
  pipelines (dev → test → prod) or your CI move the artifact between workspaces. The tool does not
  deploy; it references these. `/skills bootstrap bi` installs the Fabric toolkit that does.
- **[external] Refresh validated in the target workspace.** A scheduled/on-demand refresh succeeds
  against real credentials before the artifact is trusted. External (Fabric), surfaced not run.
- **[manual] Rollback path known.** The previous known-good version can be restored (prior deployment
  stage, git tag, or a saved `.pbip`). Write it down before promoting, not after an incident.

### 5. Post-release
- **[tool] Board reflects reality.** The shipped issues are Done, the release is posted
  (`/board update`), and their triage fields were filled *while the work was live* (`/board triage`),
  not backfilled after the fact (#306).
- **[tool] Knowledge captured.** New external references touched during the release (a dataset, a
  workspace URL, a rules file) are registered with `/knowledge add` so the next release starts from
  them instead of rediscovering them.

## Copy-paste checklist (per BI release)

```
Model & report quality
  [ ] BPA: no error-severity violations         (Bpa-GateReview.ps1 -FailOn error, via the gate)
  [ ] TMDL: breaking changes reviewed/acked      (Tmdl-DiffReview.ps1 -FailOnBreaking, via the gate)
  [ ] Report renders (pages, visuals, refs)      (manual / downstream CI)
Change review
  [ ] Merged through Board-ReviewGate + Board-Merge (green CI, no CHANGES_REQUESTED, no open threads)
  [ ] PR right-sized (<600 lines / <20 files, or broken down)
  [ ] Reviewed by someone other than the author
Versioning & changelog
  [ ] Artifact version / git tag bumped          (manual)
  [ ] CHANGELOG entry generated                  (/board changelog)
Deployment & promotion
  [ ] Promoted via deployment pipeline (dev->test->prod)   (external: Fabric)
  [ ] Refresh validated in the target workspace           (external: Fabric)
  [ ] Rollback path written down                          (manual)
Post-release
  [ ] Board updated + triage fields filled       (/board update, /board triage)
  [ ] Knowledge references captured              (/knowledge add)
```

## Why a spec, not a script

The three **[external]** deployment steps are Fabric capabilities the tool deliberately does not
reimplement, and the **[manual]** steps are judgements a tool must never fake (a "release checklist"
that auto-checks "report renders" without seeing it is worse than no checklist). So M4.1 ships the
*spec* — the shared definition of done — and wires the automatable slice into the gate (§1–§2) and the
changelog (§3). The rest is a checklist a human runs, with the tool surfacing each item it can.

## Sources
- Fabric deployment pipelines — Microsoft Learn (referenced, not vendored; install via `/skills bootstrap bi`).
- Tabular Editor Best Practice Analyzer — the objective model-quality bar (`tabular-editor:bpa-rules`).
- Keep a Changelog — the format `/board changelog` emits.
