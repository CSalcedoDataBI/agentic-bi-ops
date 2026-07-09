---
name: knowledge-registry
description: Use to capture and read a project's knowledge references by domain — add a research MD, repo, doc folder, URL, NotebookLM notebook or video to knowledge/registry.json, regenerate the KNOWLEDGE.md table, or publish it to the repo's GitHub Wiki. Distinct from MEMORY.md (agent facts) and HANDOFF.md (task resume). Triggers — "guarda esta referencia", "agrega a knowledge", "registra este link/doc/repo", "muéstrame la tabla de conocimiento", "publica el knowledge al wiki", "/knowledge add", "/knowledge list", "/knowledge gen", "/knowledge wiki".
user-invocable: false
---

# knowledge-registry

Capture and read the per-project knowledge references registry. The source of truth is
`knowledge/registry.json`; `knowledge/KNOWLEDGE.md` is a generated table grouped by domain.

## When NOT to use
- Facts the agent should recall across sessions → that is `MEMORY.md` (auto-memory).
- How to resume the current task → that is `/board handoff` / `HANDOFF.md`.
- Harvesting references already scattered in the repo → use `knowledge-harvest`.

## Add a reference
Run the engine (never hand-edit the JSON):
```
pwsh -File ${CLAUDE_PLUGIN_ROOT}/scripts/Add-KnowledgeRef.ps1 -Root . -Ref <url|path> -Domain <Domain> -Title "<title>" -Note "<one line>"
```
- The domain must be declared in the registry. If it is new and intended, pass `-NewDomain`.
- Local refs must exist on disk — the engine rejects invented paths.
- Omit `-Type` to let it infer (url / repo / md / folder / notebooklm / video); pass `-Type` to override.

## List / read
```
pwsh -File ${CLAUDE_PLUGIN_ROOT}/scripts/Get-KnowledgeInventory.ps1 -Root . -Json
```
Present the table grouped by domain. Surface health gently (broken paths, duplicates,
orphan domains, missing notes) — report, do not block.

## Regenerate the table
```
pwsh -File ${CLAUDE_PLUGIN_ROOT}/scripts/Write-KnowledgeTable.ps1 -Root .
```

## Publish to the GitHub Wiki (`/knowledge wiki`)
Publishes a Home index plus one page per domain to the repo's wiki (`<repo>.wiki.git`) —
the layer that anchors the registry to GitHub. The account is resolved from the repo owner
(CSalcedoDataBI → personal PAT, PAL-Devs → business PAT); the token travels only through a
one-shot credential helper, never the stored remote.
```
pwsh -File ${CLAUDE_PLUGIN_ROOT}/scripts/Publish-KnowledgeWiki.ps1 -Root .
```
- Requires the repo's **Wiki** feature enabled (Settings → Features → Wikis); the engine says
  so if it is off. An empty wiki is initialized on the first publish.
- `-DryRun` resolves + reports without pushing; `-PagesOnly -OutDir <dir>` writes the pages
  locally for preview without touching git.
- Wiki pages are generated — the source of truth stays `knowledge/registry.json` in the repo.
