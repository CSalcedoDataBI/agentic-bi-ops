#!/usr/bin/env bash
# board-sync.sh — Auto-fill all gaps in a GitHub Projects v2 board.
# Runs on: issue events, PR events, weekly schedule, manual dispatch.
# Requires: GH_TOKEN with 'project' + 'repo' scopes (PROJECTS_TOKEN secret).
set -euo pipefail

OWNER="${REPO_OWNER:-CSalcedoDataBI}"
REPO="${REPO_NAME:-agentic-bi-ops}"
PROJECT_NUM="${PROJECT_NUMBER:-13}"

echo "=== board-sync: $OWNER/$REPO project #$PROJECT_NUM ==="

# ── 1. Resolve project & field IDs ────────────────────────────────────────────
PROJECT=$(gh api graphql -f query='
query($owner:String!, $num:Int!) {
  user(login:$owner) {
    projectV2(number:$num) {
      id
      fields(first:30) {
        nodes {
          ... on ProjectV2SingleSelectField { id name options { id name } }
          ... on ProjectV2Field             { id name }
          ... on ProjectV2IterationField    { id name }
        }
      }
    }
  }
}' -F owner="$OWNER" -F num="$PROJECT_NUM")

PROJECT_ID=$(echo "$PROJECT" | jq -r '.data.user.projectV2.id')
STATUS_ID=$(echo "$PROJECT"  | jq -r '.data.user.projectV2.fields.nodes[] | select(.name=="Status") | .id')
DONE_OPT=$(echo "$PROJECT"   | jq -r '.data.user.projectV2.fields.nodes[] | select(.name=="Status") | .options[] | select(.name=="Done") | .id')
INPROG_OPT=$(echo "$PROJECT" | jq -r '.data.user.projectV2.fields.nodes[] | select(.name=="Status") | .options[] | select(.name=="In Progress") | .id')
TODO_OPT=$(echo "$PROJECT"   | jq -r '.data.user.projectV2.fields.nodes[] | select(.name=="Status") | .options[] | select(.name=="Todo") | .id')

echo "Project ID : $PROJECT_ID"
echo "Status field: $STATUS_ID  (Done=$DONE_OPT  InProg=$INPROG_OPT  Todo=$TODO_OPT)"

# ── 2. Load all project items ──────────────────────────────────────────────────
ITEMS=$(gh api graphql -f query='
query($proj:ID!) {
  node(id:$proj) {
    ... on ProjectV2 {
      items(first:100) {
        nodes {
          id
          fieldValues(first:20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue { field { ... on ProjectV2SingleSelectField { name } } optionId }
            }
          }
          content {
            ... on Issue {
              number state assignees(first:5) { nodes { login } }
              timelineItems(first:20 itemTypes:[CROSS_REFERENCED_EVENT]) {
                nodes {
                  ... on CrossReferencedEvent {
                    willCloseTarget
                    source {
                      ... on PullRequest { number state merged }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}' -F proj="$PROJECT_ID")

ITEM_COUNT=$(echo "$ITEMS" | jq '.data.node.items.nodes | length')
echo "Items found: $ITEM_COUNT"

# ── 3. Process each item ───────────────────────────────────────────────────────
set_status() {
  local item_id="$1" opt_id="$2"
  gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -F proj="$PROJECT_ID" -F item="$item_id" -F field="$STATUS_ID" -F opt="$opt_id" > /dev/null
}

assign_issue() {
  local issue_num="$1"
  gh api repos/"$OWNER"/"$REPO"/issues/"$issue_num"/assignees \
    -X POST -F "assignees[]=$OWNER" > /dev/null 2>&1 || true
}

echo "$ITEMS" | jq -c '.data.node.items.nodes[]' | while read -r item; do
  ITEM_ID=$(echo "$item" | jq -r '.id')
  ISSUE_NUM=$(echo "$item" | jq -r '.content.number // empty')

  # Skip non-issue items (draft notes)
  [ -z "$ISSUE_NUM" ] && continue

  ISSUE_STATE=$(echo "$item" | jq -r '.content.state')
  ASSIGNEE_COUNT=$(echo "$item" | jq '.content.assignees.nodes | length')
  CURRENT_STATUS=$(echo "$item" | jq -r '
    .fieldValues.nodes[] |
    select(.field.name == "Status") |
    .optionId // empty' | head -1)

  # Count linked PRs by state — CLOSING references only (willCloseTarget). A textual "#<n>"
  # mention in a PR body is also a cross-reference; counting it falsely marks issues Done and
  # the board's "Done -> close issue" workflow then closes them for real (issue #48).
  MERGED_PRS=$(echo "$item" | jq '[.content.timelineItems.nodes[] | select(.willCloseTarget == true) | .source | select(.merged == true)] | length')
  OPEN_PRS=$(echo "$item"   | jq '[.content.timelineItems.nodes[] | select(.willCloseTarget == true) | .source | select(.state == "OPEN")] | length')

  echo "--- Issue #$ISSUE_NUM  state=$ISSUE_STATE  assignees=$ASSIGNEE_COUNT  merged_prs=$MERGED_PRS  open_prs=$OPEN_PRS  status=$CURRENT_STATUS"

  # ── Auto-assign if empty ─────────────────────────────────────────────────
  if [ "$ASSIGNEE_COUNT" -eq 0 ]; then
    echo "  → assigning $OWNER"
    assign_issue "$ISSUE_NUM"
  fi

  # ── Sync Status ───────────────────────────────────────────────────────────
  if [ "$ISSUE_STATE" = "CLOSED" ] && [ "$CURRENT_STATUS" != "$DONE_OPT" ]; then
    echo "  → Status: Done (issue closed)"
    set_status "$ITEM_ID" "$DONE_OPT"
  elif [ "$MERGED_PRS" -gt 0 ] && [ "$CURRENT_STATUS" != "$DONE_OPT" ]; then
    echo "  → Status: Done (PR merged)"
    set_status "$ITEM_ID" "$DONE_OPT"
  elif [ "$OPEN_PRS" -gt 0 ] && [ "$CURRENT_STATUS" = "$TODO_OPT" ]; then
    echo "  → Status: In Progress (open PR)"
    set_status "$ITEM_ID" "$INPROG_OPT"
  fi
done

echo "=== board-sync complete ==="
