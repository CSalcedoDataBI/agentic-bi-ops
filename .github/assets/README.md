# Repo assets

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
