---
description: Scan the CURRENT project for untracked work (code TODOs, doc checklists/pending, plans/specs) and turn the chosen items into issues + a board plan. Targets the current repo, not the tool's.
---
You are running the agentic-board /scan command.

Apply the `project-scan` skill. Resolve the CURRENT repo with
`gh repo view --json nameWithOwner -q .nameWithOwner` and set `$env:GH_TOKEN` for THAT repo's owner
via the `gh-account` skill (personal repo → GITHUB_TOKEN_PERSONAL; PAL-Devs org repo → --account
pal-devs). Issues are created ONLY in the current repo — never the tool's repo (that's abios-feedback).

Default sources: code TODO/FIXME/HACK/XXX/BUG; unchecked `- [ ]` checklists and "pending/next steps"
sections in docs; plan/spec docs not yet tracked. Add CHANGELOG "Unreleased" or skipped/todo tests
only if the user asks.

Flow: scan (read-only) → normalize + dedupe (assign a Type) → print a proposal table → ask which
rows to create → on confirmation, create issues (label `scan`) and add them to the board. NEVER
auto-create without confirmation. Optionally apply the field preset and set Type/Status.

Arguments: $ARGUMENTS
