# agentic-bi-ops

**A Claude Code plugin that lets an AI agent run your GitHub Projects board for you.**

Ask it in plain language — *"create a board for this repo", "move these issues to Done",
"add everything labeled `bug` to the board", "close the stale ones"* — and it drives the
GitHub Projects (v2) and Issues APIs through the `gh` CLI, with safety confirmations before
anything destructive. It works across multiple GitHub accounts from one machine.

This is **Module 1** of a growing "GitOps for BI" suite (see [roadmap](#module-roadmap)).

> **See it run on itself → [SHOWCASE.md](SHOWCASE.md)** — the tool governs its own roadmap board;
> every fix was found while using it and tracked in the open (the dogfooding loop).

---

## Why

Power BI / Fabric teams track their work on GitHub Projects, but the board work is manual:
creating fields, moving cards, bulk-triaging issues, wiring CI automation. This plugin turns
those chores into natural-language requests an agent executes consistently — including the
GitHub gotchas (single-select field IDs, native sub-issues, `gh project delete` having no
`--yes` flag) that are easy to get wrong by hand.

---

## Install

```
/plugin marketplace add CSalcedoDataBI/agentic-bi-ops
/plugin install agentic-bi-ops
```

Then enable **agentic-bi-ops** in your Claude Code plugins.

---

## Quick start

After installing, use the `/board` command or just ask:

```
/board work                      # the daily driver: see pending work, pick an issue, start it
/board init                      # create a Projects board and link it to this repo
/board add #42                   # add issue #42 to the board
/board move #42 to Done          # set an item's Status
/board fill                      # detect + fill board gaps (assignees, Status, Priority, ...)
/board bulk close label:stale    # batch-close (shows a dry-run + asks first)
/board automate                  # install the CI workflow that auto-adds issues/PRs
/board templates                 # install issue forms + PR template into the repo
/board labels                    # apply the label taxonomy (bug/docs/refactor/chore/blocked/...)
/board update                    # post a high-level status update on the board
```

---

## Parallel work sessions

`/board work` can start **several independent issues at once**, each in full isolation — the
official multi-session pattern built on **git worktrees**:

```
/board work                      # pick MORE THAN ONE pending issue to batch-start
# or drive the script directly:
scripts/Board-Work.ps1 -ProjectNum <n> -Parallel 12,14,15 -Launch
```

For each issue the batch:

1. Moves it to **In Progress**, assigns you, and posts a `[abios-claim]` fingerprint.
2. Creates a **git worktree** on its own branch `issue-<n>-<slug>`, branched off a fresh
   `origin/main`. All worktrees are grouped under one sibling folder so the parent dir stays clean:

   ```
   Repos/
     agentic-bi-ops/                     ← your main working copy (untouched)
     agentic-bi-ops--worktrees/          ← one folder holds the whole fleet
       issue-129/   [issue-129-…]         ← session A
       issue-130/   [issue-130-…]         ← session B
   ```

   They share a single `.git`, so N working directories edit in parallel without colliding.
3. With `-Launch`, opens **one Windows Terminal tab per worktree** running an autonomous headless
   `claude -p` session, each briefed to take its issue all the way through **PR → review gate →
   merge**.

Monitor the fleet with `Board-Work.ps1 -Sessions` (dead-PID entries are pruned automatically).
Use `-DryRun` to preview without mutating or spawning. After a PR merges, clean its worktree with
`git worktree remove`. Only parallelize issues that don't depend on each other. Tabs require
Windows Terminal (`wt`); without it, each session opens in a standalone `pwsh` window.

---

## Setup

1. Install and authenticate the [`gh` CLI](https://cli.github.com/).
2. Provide a GitHub **Personal Access Token** (classic) with the `project` and `repo`
   scopes. The plugin reads it from an environment variable so the token never lives in the repo.

**Multi-account model.** The plugin resolves *which* account to act as, then reads that
account's token from a per-account environment variable — it never calls `gh auth switch`, so
your global `gh` state is left untouched. Configure one variable per account you use:

| Account role | Env variable | Default? |
|---|---|---|
| Primary (personal) | `GITHUB_TOKEN_PERSONAL` | ✅ used unless overridden |
| Secondary (work/org) | `GITHUB_TOKEN_BUSINESS` | used with `--account` override |

> The shipped defaults map the primary account to **CSalcedoDataBI** and the secondary to
> **PAL-Devs**. To adapt the plugin to your own accounts, edit the small map at the top of
> `scripts/Get-GhAccount.ps1` and the matching note in `skills/gh-account/SKILL.md`.

**Platform.** Token resolution reads the Windows user environment via PowerShell. On
macOS/Linux, export `GH_TOKEN` yourself before running board ops — the `gh` recipes themselves
are cross-platform.

---

## What's inside

| Component | Purpose |
|---|---|
| `gh-account` skill | Resolves the active account and injects its token per-operation. The shared foundation for every module. |
| `projects-admin` skill | Board + issue governance: fields, item moves, bulk ops, CI auto-add — with dry-run safety on destructive actions. |
| `abios-feedback` skill | Capture tool improvements found while working in any project, sanitized so private data never leaks back here. |
| `project-scan` skill | Scan the CURRENT project for untracked work (code TODOs, doc checklists/pending, plans/specs) and turn chosen items into issues + a board plan. |
| Field presets | One-step localized governance fields (Status/Priority/Type/Area/Estimate/Target) in EN or ES. |
| `/board`, `/scan` commands | Natural-language entry points for the above. |

---

## Contributing safely (private → public)

This tool improves itself: most fixes are discovered while using it inside **private** projects.
The hard rule is that the cause may be private, but the contribution must be public-only.

Two layers protect this repo:

1. **Discipline** — the `abios-feedback` skill captures each improvement abstracted to the public
   tool (no repo names, client names, data, GUIDs, or paths).
2. **A guard you can't forget** — after cloning, run once:
   ```
   powershell -File scripts/install-guard.ps1
   ```
   This wires a `pre-commit` + `pre-push` hook that **blocks** any commit/push whose added lines
   contain a known secret pattern or a term from your local `.abios/private-denylist.txt`
   (gitignored — never committed). Seed that file with your own private fingerprints.

It's defense-in-depth, not a guarantee: a denylist only catches terms you list, so keep layer 1
honest. Override (`--no-verify`) only for a confirmed false positive.

---

## GitHub best practices — enforced by design

The `/board work` flow doesn't just *allow* good GitHub hygiene — it **enforces** it. Checked
against the official guides ([Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/best-practices-for-projects),
[GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow),
[Pull requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/getting-started/best-practices-for-pull-requests),
[Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/configuring-issues/planning-and-tracking-work-for-your-team-or-project)):

| Official practice | How the tool enforces it |
|---|---|
| Branch per change, descriptive name | `work` creates `issue-<num>-<slug>` on start |
| PR for every change, issue auto-closed | step 5 mandates a PR with `Closes #<num>` — never direct to main |
| Right identity per repo | `New-BoardPR.ps1` resolves the account from the repo OWNER, pushes with a one-shot credential (remote never rewritten), opens/updates the PR |
| Merge only after review | **review gate**: Copilot review request + CI checks + unresolved threads; exit 0 gates the merge; honest self-review fallback |
| Small, focused PRs | gate warns over 600 lines / 20 files and suggests a sub-issue split |
| Delete branch after merge | merge flow uses `--delete-branch` |
| Break down large issues | `Board-Breakdown.ps1` creates native sub-issues (progress column fills itself) |
| Custom-field metadata | field presets + `Board-Fill` (assignees, Status, Priority, Size, Type) |
| Issue templates & labels | `/board templates` (forms + PR template) and `/board labels` (taxonomy) |
| Status updates | `/board update` posts high-level progress on the board |
| Dependencies respected | `[BLOCKED]` items are flagged and refused by `-Start` |
| Single source of truth | one board ⇄ one repo, resolve-before-create, backup-before-delete |

Honestly out of scope (GitHub exposes no API): view layouts, charts/insights, project templates.

---

## Module roadmap

| Module | Description | Foundation |
|---|---|---|
| **M1** (current) | Cross-account GitHub Projects & issues governance | `gh-account` |
| **M2** (in progress) | PBIP / Fabric git ops — branch-per-report, **TMDL diff review** (breaking schema-change detection, wired into the review gate) | `gh-account`, `tmdl-review` |
| **M3** | Semantic-model review agents wired to the board | `gh-account` |
| **M4** (in progress) | BI release automation — **changelog generation** from board Done issues (`/board changelog`) | `gh-account` |

---

## License

MIT — see [LICENSE](./LICENSE).
