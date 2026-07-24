---
description: Manage the project knowledge references registry by domain (add/harvest/list/gen/wiki). Versioned in knowledge/registry.json + generated KNOWLEDGE.md.
---

# /knowledge

Route the request to the right knowledge-ops skill.

- `add <url|path> [domain] [note]` → invoke **knowledge-registry** (Add-KnowledgeRef).
- `harvest` → invoke **knowledge-harvest** (scan repo → pick → add).
- `list [domain]` → invoke **knowledge-registry** (Get-KnowledgeInventory) and print the table.
- `gen` → invoke **knowledge-registry** (Write-KnowledgeTable).
- `wiki` → invoke **knowledge-registry** (Publish-KnowledgeWiki) to publish the registry to the repo's GitHub Wiki. **Deprecated** — delegates to `/docs wiki` (Publish-DocsWiki.ps1), which is now the single publisher for all wiki content (product docs + knowledge registry in one push).
- no argument → show this menu.

The registry lives at `knowledge/registry.json`; the readable table at `knowledge/KNOWLEDGE.md`.
`KNOWLEDGE.md` is generated — never edit it by hand. `KNOWLEDGE.md` is the catalog of external
references by domain, distinct from `MEMORY.md` (agent facts) and `HANDOFF.md` (task resume).
