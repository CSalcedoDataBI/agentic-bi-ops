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
/board work                      # see pending issues across ALL your boards and start one
/board init                      # create a Projects board and link it to this repo
/board add #42                   # add issue #42 to the board
/board move #42 to Done          # set an item's Status
/board bulk close label:stale    # batch-close (shows a dry-run + asks first)
/board automate                  # install the CI workflow that auto-adds issues/PRs
```

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

## Module roadmap

| Module | Description | Foundation |
|---|---|---|
| **M1** (current) | Cross-account GitHub Projects & issues governance | `gh-account` |
| **M2** | PBIP / Fabric git ops (branch-per-report, TMDL diff review) | `gh-account` |
| **M3** | Semantic-model review agents wired to the board | `gh-account` |
| **M4** | BI release automation | `gh-account` |

---

## License

MIT — see [LICENSE](./LICENSE).
