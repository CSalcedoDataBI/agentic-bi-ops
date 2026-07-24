---
description: Publish all wiki pages (product docs + knowledge registry) in a single push.
---

# /docs

Route the request to the docs publisher.

- `wiki` → run `Publish-DocsWiki.ps1` to publish all wiki pages in one clone → commit → push.
- no argument → show this menu.

## What gets published

`/docs wiki` generates and pushes every wiki page in one operation:

**Product docs** (always):
- `Docs-Home` — from `README.md` (HTML stripped)
- `Docs-Command-<X>` — one page per `commands/*.md` file (frontmatter stripped)

**Knowledge registry** (when `knowledge/registry.json` exists):
- `Home` — index of domains and reference counts
- `Knowledge-<Domain>` — one page per domain in the registry

**Navigation** (always):
- `_Sidebar` — links to all product docs pages + all knowledge domain pages
- `_Footer` — "generated from the repository" notice

All pages carry a `<!-- GENERATED -->` marker. Never edit the wiki directly — changes will be
overwritten on the next publish. Source of truth stays in the repo.

## Prerequisites

The wiki must be initialized before the first publish. If you see an error, follow the
steps it prints to create the first page via the GitHub web UI, then re-run.

`/knowledge wiki` is a deprecated alias for `/docs wiki` — it delegates here.
