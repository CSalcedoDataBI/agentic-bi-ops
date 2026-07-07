---
name: knowledge-registry
description: Use to capture and read a project's knowledge references by domain — add a research MD, repo, doc folder, URL, NotebookLM notebook or video to knowledge/registry.json and regenerate the KNOWLEDGE.md table. Distinct from MEMORY.md (agent facts) and HANDOFF.md (task resume). Triggers — "guarda esta referencia", "agrega a knowledge", "registra este link/doc/repo", "muéstrame la tabla de conocimiento", "/knowledge add", "/knowledge list", "/knowledge gen".
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
