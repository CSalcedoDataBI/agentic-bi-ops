# automation — CI Auto-Add Workflow

Drop-in GitHub Actions workflow that automatically adds newly opened or labeled issues and PRs to a Projects v2 board. Place this file in the consumer repo's `.github/workflows/` directory.

---

## Workflow template

```yaml
# .github/workflows/add-to-project.yml  (place in the CONSUMER repo)
name: Add issues/PRs to board
on:
  issues: { types: [opened, labeled] }
  pull_request: { types: [opened, labeled] }
jobs:
  add:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/add-to-project@v1
        with:
          project-url: https://github.com/users/<owner>/projects/<num>
          github-token: ${{ secrets.ADD_TO_PROJECT_PAT }}
          labeled: board        # only items carrying this label
```

---

## Notes

- **`ADD_TO_PROJECT_PAT`** must be a classic PAT with the `project` scope. Go to GitHub → Settings → Developer settings → Personal access tokens → Generate new token, check `project`. Add it as a repository secret named `ADD_TO_PROJECT_PAT` in the consumer repo's Settings → Secrets and variables → Actions.

- **For a user-owned board** the `project-url` is `https://github.com/users/<owner>/projects/<num>`. For an **organization-owned board**, use `https://github.com/orgs/<org>/projects/<num>` instead.

- **Label filter:** the `labeled: board` line means the workflow only fires when the item carries the `board` label. Remove the line to add every opened issue/PR. Use `gh label create board --color 0E8A16 --repo <owner>/<repo> --force` (see `issue-ops.md`) to ensure the label exists before triggering.

- **`actions/add-to-project`** is the official action maintained by GitHub (MIT license, repository at `github/add-to-project`). Pin to `@v1` or a specific SHA for reproducibility.

- The action does NOT move items between columns or set field values. For automated Status transitions (e.g. move to "Done" when an issue closes), add a second step using the `gh project item-edit` recipe from `board-ops.md` wrapped in a shell step with the PAT injected as `GH_TOKEN`.
