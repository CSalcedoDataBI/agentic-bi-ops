# Contributing to agentic-board

Thanks for helping improve **agentic-board** — the Claude Code plugin that runs coding agents
off your real GitHub Projects board. This guide covers the one rule that is non-obvious (private
→ public), how to set up, and how a change gets from an idea to a merged PR.

## The one rule: private cause, public contribution

This tool improves itself. Most fixes are discovered while using it inside **private** projects.
The hard rule is: **the cause may be private, but the contribution must be public-only** — no repo
names, client names, data, GUIDs, tokens, or file paths from a private project may land here.

Two layers protect the repo — please keep both honest:

1. **Discipline.** The `abios-feedback` skill captures each improvement abstracted to the public
   tool. When you file an issue or open a PR, describe the *general* problem, not the private case.
2. **A guard you can't forget.** After cloning, run once:
   ```
   powershell -File scripts/install-guard.ps1
   ```
   This wires `pre-commit` + `pre-push` hooks that **block** any commit/push whose added lines
   contain a known secret pattern or a term from your local `.abios/private-denylist.txt`
   (gitignored — seed it with your own private fingerprints). Only override (`--no-verify`) for a
   confirmed false positive.

## Setup

1. Install and authenticate the [`gh` CLI](https://cli.github.com/).
2. Provide a GitHub **Personal Access Token** (classic) with the `project` and `repo` scopes. The
   plugin reads it from a per-account environment variable — never from the repo. On Windows the
   default is the user env var `GITHUB_TOKEN_PERSONAL`; on macOS/Linux export `GH_TOKEN` yourself.
3. Install [Pester 5](https://pester.dev/) to run the test suite (`Install-Module Pester -MinimumVersion 5.5.0`).

## Making a change

The tool can drive its own contribution flow — the fastest path is to let it:

```
/board work                      # pick a pending issue and start it (branch + worktree)
```

That moves the issue to **In Progress**, creates `issue-<num>-<slug>`, and briefs you with the
full context. Or do it by hand:

1. **Branch per change.** `git checkout -b issue-<num>-<slug>` off a fresh `main`.
2. **One issue, one focused PR.** Small PRs review better; the review gate warns past 600 lines /
   20 files and suggests splitting with sub-issues.
3. **Open a PR that closes the issue.** The [PR template](.github/PULL_REQUEST_TEMPLATE.md) has a
   `Closes #` slot — fill it so the merge closes the issue and updates the board automatically.
   Never commit board-tracked work directly to `main`.
4. **Pass the review gate.** CI (the Pester suite) must be green, a code review requested, and no
   unresolved threads. If no reviewer is available, self-review the full `gh pr diff` and say so.

## Tests

The suite lives in `plugins/agentic-board/tests/`. Run it locally before
opening a PR — CI runs the same suite on every PR and **blocks the merge on any failure**:

```powershell
Invoke-Pester -Path plugins/agentic-board/tests
```

New behavior needs a test. Side-effecting scripts expose a dot-source guard (e.g.
`$env:ABIOS_BOARDFILL_DOTSOURCE`) so their pure helpers can be unit-tested without hitting `gh`.

## Conventions

- **Commits & board content in English**, [Conventional Commits](https://www.conventionalcommits.org/)
  style (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- **PowerShell** for scripts; match the surrounding style.
- **Don't rename internal state keys casually.** The state dir and `ABIOS_*` env vars are on-disk
  identifiers on users' machines — renaming them orphans live sessions and backups. The current
  state dir is `.agentic-board/` (with `~/.agentic-board/backups`); the pre-rebrand `.agentic-bi-ops/`
  is migrated transparently. Both are resolved through the single `Get-AbiosStateDir` helper —
  never hard-code either literal elsewhere, and any future rename must go through that helper with
  the same one-time migration + fallback.
- Keep the `gh` remote a bare URL; auth flows through the token env var, never a PAT baked into the
  URL.

## Docs

Two parts of `README.md` are **generated, not hand-written**, so they can't drift: the command
catalog (from each `commands/*.md` frontmatter `description`) and the version string (from
plugin.json). They live between `<!-- BEGIN:commands -->`/`<!-- END:commands -->` and
`<!-- BEGIN:version -->`/`<!-- END:version -->` markers — edit the *source*, then regenerate:

```powershell
plugins/agentic-board/scripts/Update-Docs.ps1            # rewrite the marked regions in place
plugins/agentic-board/scripts/Update-Docs.ps1 -Check     # exit 1 if the README is stale (CI gate)
```

Everything outside the markers stays hand-written. `-Check` is exit-code clean (0 fresh / 1 stale)
so a docs-freshness gate can block a PR that edited a command's description without regenerating.

## Releasing

`plugins/agentic-board/.claude-plugin/plugin.json` is the **single source of truth** for the
version; the plugin entry in `.claude-plugin/marketplace.json` mirrors its `name` + `description`
(nothing restates the version). `scripts/New-Release.ps1` prepares a release and **stops before
committing** so you review the diff first:

```powershell
# from the repo root
plugins/agentic-board/scripts/New-Release.ps1 -Check          # validate manifests + semver (no writes)
plugins/agentic-board/scripts/New-Release.ps1 -Bump minor -DryRun   # preview current -> next
plugins/agentic-board/scripts/New-Release.ps1 -Bump patch     # bump plugin.json + fold the CHANGELOG
```

It bumps the version (targeted, so the rest of `plugin.json` is byte-preserved), folds the board's
Done issues into `CHANGELOG.md` under the new version (via `Board-Changelog.ps1`), and validates
that `marketplace.json` hasn't drifted from `plugin.json` (`-SyncManifest` rewrites it from the
source of truth). Then review `git diff` and commit `chore(release): X.Y.Z` yourself — tagging and
pushing stay manual. `-Check` is exit-code clean (0 ok / 1 drift) so a CI gate can call it.

## Good first issues

New here? Look for the [`good first issue`](https://github.com/CSalcedoDataBI/agentic-board/labels/good%20first%20issue)
label. Questions or a design idea? Open an issue with the **feature** or **task** template first —
it's cheaper to align before code.

## License

By contributing you agree your work is licensed under the repo's [MIT License](./LICENSE).
