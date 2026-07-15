# Repo assets

## README demo GIFs (#210)

Two above-the-fold GIFs in the root `README.md`:

| GIF | Source | Shows |
|-----|--------|-------|
| `board-install.gif` | `board-demo.ps1` + `board-install.tape` | install → **AGENTIC BOARD** banner → `/board` menu |
| `board-loop.gif` | `board-loop.ps1` + `board-loop.tape` | the work loop: what's pending → start #17 → review-gated PR → Done |

They are **scripted playbacks**, not live sessions: the `.ps1` files simulate typing so the
recording is deterministic and reproducible. The commands shown are the real ones, and the
banner is real too — `Welcome-SessionStartHook.ps1` (#270) shows it on the first run after
install.

### Regenerating

Needs **VHS**, **ffmpeg**, and **ttyd** on PATH. Windows has no native ttyd build, so grab
`ttyd.win32.exe` from [tsl0922/ttyd](https://github.com/tsl0922/ttyd) releases and drop it on
PATH renamed to `ttyd.exe`:

```powershell
winget install charmbracelet.vhs      # also pulls ffmpeg
# ttyd: download ttyd.win32.exe -> rename to ttyd.exe -> put it on PATH
ttyd --version                        # verify (a terminal opened BEFORE a PATH change won't see it)
```

Then, **from the repo root**:

```powershell
vhs .github/assets/board-install.tape
vhs .github/assets/board-loop.tape
```

Tweak size/zoom via `Set FontSize` / `Set Width` / `Set Height` in the `.tape` files.

## `social-preview.png` (1280×640)

GitHub social-preview / Open Graph card for the repository (#212).

**Uploading is a one-time manual step** — GitHub does not expose the social-preview
image via the REST API or `gh` CLI. Upload it in the web UI:

> **Settings → General → Social preview → Edit → Upload an image** → pick
> `.github/assets/social-preview.png`.

### Regenerating

Source is `social-preview.html` (self-contained). Render at 1280×640 and export PNG,
e.g. serve the folder and screenshot the viewport:

```bash
python -m http.server 8791          # from .github/assets/
# then screenshot http://localhost:8791/social-preview.html at 1280x640
```
