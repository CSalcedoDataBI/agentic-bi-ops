---
description: Manage the project knowledge references registry by domain (add/harvest/list/gen). Versioned in knowledge/registry.json + generated KNOWLEDGE.md.
---

# /knowledge

Route the request to the right knowledge-ops skill.

- `add <url|path> [domain] [note]` → invoke **knowledge-registry** (Add-KnowledgeRef).
- `harvest` → invoke **knowledge-harvest** (scan repo → pick → add).
- `list [domain]` → invoke **knowledge-registry** (Get-KnowledgeInventory) and print the table.
- `gen` → invoke **knowledge-registry** (Write-KnowledgeTable).
- no argument → show this menu.

The registry lives at `knowledge/registry.json`; the readable table at `knowledge/KNOWLEDGE.md`.
`KNOWLEDGE.md` is generated — never edit it by hand. `KNOWLEDGE.md` is the catalog of external
references by domain, distinct from `MEMORY.md` (agent facts) and `HANDOFF.md` (task resume).
