# agentic-bi-ops

GitOps for BI with AI agents — a Claude Code plugin. Module 1: cross-account GitHub Projects & issues governance.

---

## Install

```
/plugin marketplace add CSalcedoDataBI/agentic-bi-ops
/plugin install agentic-bi-ops
```

Then enable the `agentic-bi-ops` plugin in your Claude Code settings.

---

## Prerequisites

- **Platform: Windows.** Token resolution reads the Windows USER registry via PowerShell
  (`[System.Environment]::GetEnvironmentVariable(..., 'User')`). On macOS/Linux, export `GH_TOKEN`
  yourself before running board ops; the `gh project`/`gh issue` recipes themselves are cross-platform.
- `gh` CLI installed and authenticated.
- Windows user environment variables:
  - `GITHUB_TOKEN_PERSONAL` (**required**) — PAT for `CSalcedoDataBI`, scopes: `project` + `repo`.
  - `GITHUB_TOKEN_BUSINESS` (optional) — PAT for `PAL-Devs`, same scopes.

---

## What's inside

| Component | Purpose |
|---|---|
| `gh-account` | Cross-account token resolution. Default account: `CSalcedoDataBI`. |
| `projects-admin` | Board + issue governance across accounts and projects. |
| `/board` | Slash command — manage GitHub Projects boards and issues. |

---

## Module roadmap

| Module | Description | Foundation |
|---|---|---|
| **M1** (current) | Cross-account GitHub Projects & issues governance | `gh-account` |
| **M2** | PBIP / Fabric git ops | `gh-account` |
| **M3** | Semantic-model review agents | `gh-account` |
| **M4** | BI release automation | `gh-account` |

All modules share the `gh-account` token-resolution foundation.

---

## License

MIT — see [LICENSE](./LICENSE).
