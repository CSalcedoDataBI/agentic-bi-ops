---
description: Administer/automate a GitHub Projects board (work/init/add/move/field/bulk/fill/automate). Defaults to the CSalcedoDataBI account.
---
You are running the agentic-bi-ops /board command.

**If $ARGUMENTS is empty or only whitespace, do NOT run anything yet.** Show this menu and wait
for the user to pick (they can answer with just the number):

```
¿Qué quieres hacer con el board?

1. work             → ver qué issues están pendientes (en todos los boards) y empezar a trabajar uno
2. fill --dry-run   → ver qué gaps hay (assignees, Status, Priority, Size, Type) SIN cambiar nada
3. fill --auto      → llenar todos los gaps automáticamente (convierte drafts a issues reales)
4. fill             → llenar gaps pidiendo confirmación antes de ejecutar
5. init             → crear/configurar el board de este repo
6. add <url>        → añadir un issue/PR al board
7. move             → cambiar el Status de un item
8. field            → crear campos o llenar un campo en todos los items por regla
9. bulk             → mover/cerrar/etiquetar muchos items a la vez
10. automate        → instalar CI que sincroniza el board solo
11. templates       → instalar issue forms (bug/feature/task) + PR template en el repo actual
12. labels          → aplicar la taxonomia de labels (bug/docs/refactor/chore/blocked/...) al repo
```

When they answer (number or name), execute that sub-action following the instructions below.

First apply the `gh-account` skill to set `$env:GH_TOKEN` for the right account (default
CSalcedoDataBI; honor an explicit `--account pal-devs` in the arguments). Never run `gh auth switch`.

Then apply the `projects-admin` skill. Parse the request into ONE of these sub-actions and run the
matching recipe from the projects-admin references:

- **work** — the daily driver: show pending work and start an issue, via `scripts/Board-Work.ps1`.
  Conversational flow — steps 0 and 1 are QUESTIONS: ask, then WAIT for the answer before running:
  0. **Account.** Check which PATs are configured (Windows USER registry):
     `[Environment]::GetEnvironmentVariable('GITHUB_TOKEN_PERSONAL','User')` and the same for
     `GITHUB_TOKEN_BUSINESS`. If BOTH exist, ask which account to use — `1. CSalcedoDataBI
     (personal, default)` / `2. PAL-Devs (business)` — and for business pass
     `-TokenVar GITHUB_TOKEN_BUSINESS -Owner PAL-Devs` to every Board-Work call. If only ONE
     exists, use it silently — do not ask.
  1. **Scope.** Detect the current repo: `git remote get-url origin` → `<owner/name>`. If the cwd
     is a clone of a GitHub repo, ask: "¿Boards de ESTE repo (<owner/name>) o TODOS los boards de
     la cuenta?" — a repo can have several linked boards.
     - This repo → `-ListBoards -Repo <owner/name>` (only boards LINKED to the repo, via
       `repository.projectsV2`). If exactly ONE board comes back, skip step 2 and continue with it.
     - All / not inside a git repo (skip the question then) → `-ListBoards` (every board of the
       account, most pending first).
  2. **Pick a board.** Show the listing (pending counts + URLs) and ask which board.
  3. **Pick an issue.** Run with `-ProjectNum <n>` — pending items sorted by Priority. Show them
     and ask which issue to start. Draft notes appear flagged: they must be converted with
     `/board fill` before they can be started.
  4. **Start it.** Run with `-ProjectNum <n> -Start <issueNum> -Branch` — moves the item to
     In Progress, assigns the owner, creates + checks out the work branch `issue-<num>-<slug>`
     (when the cwd is a clone of the issue's repo), and prints the full issue context (body,
     labels, sub-issues). Then CONTINUE WORKING that issue in this session: treat the printed
     context as the task briefing. Always pass `-Branch` when the issue belongs to the current
     repo. `--dry-run` previews without mutating; a CLOSED issue is refused.
     - **Too big for one PR?** Break it down FIRST with
       `scripts/Board-Breakdown.ps1 -Parent <issueNum> -Tasks "child A", "child B"` — creates
       native sub-issues (Sub-issues progress fills itself) — then start one child. Use a
       checkbox task list in the parent body instead when the pieces are too small for issues.
  5. **Finish with a PR + review gate — MANDATORY.** When the work is done:
     a. Push the branch and open a PR whose body contains `Closes #<issueNum>`. NEVER commit
        board-tracked issue work directly to main — the PR is what makes GitHub fill the
        board's "Linked pull requests" column (a system column no API can write). This
        overrides any general commit-directly-to-main workflow rule for issues started via `work`.
     b. Run `scripts/Board-ReviewGate.ps1 -Repo <owner/name> -PR <n>` — it requests a Copilot
        code review when available, waits for CI checks, waits for the review, and prints
        decision + feedback + unresolved threads. Exit 0 = gate passed; exit 1 = blocked.
        Address the printed feedback with new commits, push, and RE-RUN the gate until it
        passes. If the `second-opinion` skill is available, use it as an extra reviewer.
        If no reviewer is available at all, an explicit self-review of `gh pr diff <n>` is
        obligatory before merging — and say so honestly in your report.
     c. Only after the gate passes: `gh pr merge <n> --squash --delete-branch`.
     - Optional, once per repo: `Board-ReviewGate.ps1 -Repo <owner/name> -InstallRuleset`
       installs a ruleset requiring PRs into the default branch (admins keep bypass — say so).
  - If many pending items lack Priority/Size, suggest `/board fill` to triage them first.
- **init** — create a board and fill it coherently: title, short description, README, and link the
  repo (references/board-ops.md). Tell the user the two UI-only items (Default repository pick, View
  name/layout) need one click in settings — do not claim they were set.
- **add** — add an issue/PR to the board (references/issue-ops.md)
- **move** — set an item's Status (references/board-ops.md single-select recipe)
- **field** — create fields / apply a field preset (`apply en|es`) / set Status/Priority/Type values /
  **bulk-fill any custom field across EVERY item by rule** (`scripts/Set-BoardField.ps1` — single-select
  by title-prefix map, or text by `{title}` template — idempotent, retries 502s)
  (references/field-presets.md + board-ops.md). Visibility-per-view and group-by are UI-only — say so.
- **bulk** — batch move/close/label across many items (references/issue-ops.md)
- **fill** — detect and fill ALL gaps across the board by running `scripts/Board-Fill.ps1`
  (pass -Owner, -Repo, -ProjectNum for the current repo's board):
  - The script converts any draft notes to REAL issues in the repo first, then fills gaps:
    Assignees (owner), Status (from issue/PR state), Priority (P2 Medium), Size (M),
    Type (from labels, else Feature).
  - No flags: run with neither -DryRun nor -Auto — the script prints the plan and asks (s/n).
  - `--dry-run`: run with -DryRun — plan only, executes nothing.
  - `--auto`: run with -Auto — fills everything without asking. Use for CI or when already approved.
  - NOTE: Linked PRs and Sub-issues progress are system-derived columns — GitHub sets them
    automatically from PR mentions and sub-issue state. They are NOT writable via API; do not
    attempt to fill them and explain this to the user if asked.
  - NOTE: which columns a VIEW displays is UI-only — if fields look "empty" on the board page,
    tell the user to click `+` at the right of the view header and enable Priority/Size/Type.
- **automate** — install the actions/add-to-project CI workflow (references/automation.md)
- **templates** — install issue forms + PR template into the current repo working copy by running
  `scripts/Install-RepoTemplates.ps1` (default `-Path .`, repo derived from origin):
  - Drops `.github/ISSUE_TEMPLATE/{bug,feature,task,config}.yml` and
    `.github/PULL_REQUEST_TEMPLATE.md` (with the mandatory `Closes #` slot).
  - Ensures the labels the forms reference exist (`bug`/`feature`/`task`) — GitHub silently
    ignores a form label that does not exist.
  - Existing files are SKIPPED (never overwrite a repo's customized templates); `--force`
    overwrites. The script only touches the working copy — commit through the normal flow
    (PR when the work is board-tracked).
- **labels** — apply the label taxonomy preset by running `scripts/Apply-LabelPreset.ps1`
  (repo derived from origin, or `-Repo owner/name`). Idempotent `gh label create --force` from
  `presets/labels.json`: `bug`/`docs`/`refactor`/`chore` feed Board-Fill Type detection,
  `blocked` feeds the work dependency check, `roadmap`/`plan`/`plan-task` feed plan tracking.
  Never deletes existing labels.

ALWAYS END WITH THE BOARD LINK (mandatory): every response about a board operation — plan,
result, or error — must end with the board URL so the user can open it in one click:
`https://github.com/users/<owner>/projects/<num>` (or `/orgs/<org>/projects/<num>` for org boards).

SAFETY (mandatory, see references/best-practices.md):
- Before init/add/plan, **resolve-or-reuse** the repo's board with `scripts/Resolve-Board.ps1` —
  never create a duplicate board with a blind `gh project create`.
- Before ANY board delete, **always run `scripts/Backup-Board.ps1` first** (JSON snapshot + live
  clone) — unconditionally, without asking. The delete itself still needs explicit confirmation.
- For any destructive action (delete, bulk close/move), print a dry-run of exactly what would
  change and confirm BEFORE mutating.

Arguments: $ARGUMENTS
