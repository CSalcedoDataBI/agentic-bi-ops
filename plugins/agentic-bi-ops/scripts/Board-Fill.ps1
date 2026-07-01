<#
.SYNOPSIS
    Detect and fill gaps in a GitHub Projects v2 board.

.DESCRIPTION
    Reads all items from a GitHub Projects v2 board and detects gaps:
    missing assignees and wrong/missing Status fields. Then fills them
    according to the rules below.

    Fill rules:
      Assignees  : if empty, assign the board owner
      Status     : issue CLOSED -> Done
                   issue OPEN + merged PR -> Done
                   issue OPEN + open PR   -> In Progress
                   issue OPEN + no PR     -> Todo

    Linked PRs and Sub-issues progress are system-derived columns.
    GitHub sets them automatically. They are not writable via API.

.PARAMETER Owner
    GitHub username or org that owns the project board.
    Defaults to CSalcedoDataBI.

.PARAMETER Repo
    owner/repo string (e.g. "CSalcedoDataBI/agentic-bi-ops").
    Used for issue assignment calls.

.PARAMETER ProjectNum
    GitHub Projects v2 number (e.g. 13).

.PARAMETER DryRun
    Print the plan without executing any changes.

.PARAMETER Auto
    Execute changes without asking for confirmation.
    Equivalent to the CI board-sync.sh behaviour.

.EXAMPLE
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/agentic-bi-ops -ProjectNum 13 -DryRun
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/agentic-bi-ops -ProjectNum 13
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/agentic-bi-ops -ProjectNum 13 -Auto
#>
[CmdletBinding()]
param(
    [string]$Owner      = "CSalcedoDataBI",
    [string]$Repo       = "",
    [int]   $ProjectNum = 13,
    [switch]$DryRun,
    [switch]$Auto
)

$ErrorActionPreference = "Stop"

# ── 0. Token ──────────────────────────────────────────────────────────────────
$env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN_PERSONAL", "User")
if (-not $env:GH_TOKEN) { throw "GITHUB_TOKEN_PERSONAL not set in Windows USER environment." }
if (-not $Repo) { $Repo = "$Owner/agentic-bi-ops" }

$mode = if ($DryRun) { "DRY-RUN" } elseif ($Auto) { "AUTO" } else { "INTERACTIVE" }
Write-Host "=== Board-Fill  Owner=$Owner  Project=#$ProjectNum  Mode=$mode ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Resolve project + field IDs ────────────────────────────────────────────
$projData = gh api graphql -f query='
query($owner:String!, $num:Int!) {
  user(login:$owner) {
    projectV2(number:$num) {
      id
      fields(first:30) {
        nodes {
          ... on ProjectV2SingleSelectField { id name options { id name } }
        }
      }
    }
  }
}' -F owner=$Owner -F num=$ProjectNum | ConvertFrom-Json

$projectId  = $projData.data.user.projectV2.id
$statusNode = $projData.data.user.projectV2.fields.nodes | Where-Object { $_.name -eq "Status" }
$statusId   = $statusNode.id
$doneId     = ($statusNode.options | Where-Object { $_.name -eq "Done" }).id
$inProgId   = ($statusNode.options | Where-Object { $_.name -eq "In Progress" }).id
$todoId     = ($statusNode.options | Where-Object { $_.name -eq "Todo" }).id

# ── 2. Load all board items ────────────────────────────────────────────────────
$itemData = gh api graphql -f query='
query($proj:ID!) {
  node(id:$proj) {
    ... on ProjectV2 {
      items(first:100) {
        nodes {
          id
          fieldValues(first:20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                field { ... on ProjectV2SingleSelectField { name } }
                optionId
                name
              }
            }
          }
          content {
            ... on Issue {
              number title state
              assignees(first:5) { nodes { login } }
              timelineItems(first:20 itemTypes:[CROSS_REFERENCED_EVENT]) {
                nodes {
                  ... on CrossReferencedEvent {
                    source { ... on PullRequest { number state merged } }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}' -F proj=$projectId | ConvertFrom-Json

$items = $itemData.data.node.items.nodes

# ── 3. Detect gaps ─────────────────────────────────────────────────────────────
$plan = @()

foreach ($item in $items) {
    $c = $item.content
    if (-not $c.number) { continue }

    $assigneeCount = $c.assignees.nodes.Count
    $currentOptId  = ($item.fieldValues.nodes | Where-Object { $_.field.name -eq "Status" }).optionId
    $currentName   = ($item.fieldValues.nodes | Where-Object { $_.field.name -eq "Status" }).name

    $mergedPRs = @($c.timelineItems.nodes.source | Where-Object { $_.merged -eq $true })
    $openPRs   = @($c.timelineItems.nodes.source | Where-Object { $_.state  -eq "OPEN"  })

    $changes = @()

    if ($assigneeCount -eq 0) {
        $changes += [PSCustomObject]@{ Type="assignee"; Display="Assignee vacio -> asignar $Owner" }
    }

    $targetOptId = $null; $targetName = $null
    if     ($c.state -eq "CLOSED"     -and $currentOptId -ne $doneId)  { $targetOptId=$doneId;   $targetName="Done (issue cerrado)" }
    elseif ($mergedPRs.Count -gt 0    -and $currentOptId -ne $doneId)  { $targetOptId=$doneId;   $targetName="Done (PR mergeado)" }
    elseif ($openPRs.Count   -gt 0    -and $currentOptId -eq $todoId)  { $targetOptId=$inProgId; $targetName="In Progress (PR abierto)" }
    elseif (-not $currentOptId)                                          { $targetOptId=$todoId;   $targetName="Todo (sin PR ni cierre)" }

    if ($targetOptId) {
        $changes += [PSCustomObject]@{ Type="status"; TargetId=$targetOptId; Display="Status [$currentName] -> $targetName" }
    }

    if ($changes.Count -gt 0) {
        $plan += [PSCustomObject]@{
            ItemId   = $item.id
            IssueNum = $c.number
            Title    = $c.title
            State    = $c.state
            Changes  = $changes
        }
    }
}

# ── 4. Print plan ──────────────────────────────────────────────────────────────
if ($plan.Count -eq 0) {
    Write-Host "Board completo. Sin gaps detectados." -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTA: Linked PRs y Sub-issues progress son columnas del sistema, no escribibles via API."
    exit 0
}

Write-Host "Plan de cambios:" -ForegroundColor Yellow
foreach ($entry in $plan) {
    Write-Host ""
    Write-Host "  #$($entry.IssueNum) $($entry.Title) [$($entry.State)]" -ForegroundColor Yellow
    foreach ($ch in $entry.Changes) { Write-Host "    -> $($ch.Display)" }
}
Write-Host ""
Write-Host "Total: $($plan.Count) item(s) con gaps." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host ""
    Write-Host "Modo DRY-RUN — ningun cambio ejecutado." -ForegroundColor Gray
    Write-Host "NOTA: Linked PRs y Sub-issues progress son columnas del sistema, no escribibles via API."
    exit 0
}

# ── 5. Confirm (interactive) ───────────────────────────────────────────────────
if (-not $Auto) {
    Write-Host ""
    $confirm = Read-Host "Aplicar estos cambios? (s/n)"
    if ($confirm -notmatch '^[sySY]') { Write-Host "Cancelado." -ForegroundColor Gray; exit 0 }
}

# ── 6. Execute ─────────────────────────────────────────────────────────────────
$ok = 0; $fail = 0

foreach ($entry in $plan) {
    foreach ($ch in $entry.Changes) {
        try {
            if ($ch.Type -eq "assignee") {
                $assignUrl = "repos/$Repo/issues/$($entry.IssueNum)/assignees"
                gh api $assignUrl -X POST -F "assignees[]=$Owner" | Out-Null
                Write-Host "  OK  #$($entry.IssueNum) assignee -> $Owner" -ForegroundColor Green
                $ok++
            }
            elseif ($ch.Type -eq "status") {
                gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -F proj=$projectId -F item=$entry.ItemId -F field=$statusId -F opt=$ch.TargetId | Out-Null
                Write-Host "  OK  #$($entry.IssueNum) $($ch.Display)" -ForegroundColor Green
                $ok++
            }
        } catch {
            Write-Host "  FAIL #$($entry.IssueNum): $_" -ForegroundColor Red
            $fail++
        }
    }
}

Write-Host ""
Write-Host "=== Completado: $ok OK  $fail fallos ===" -ForegroundColor Cyan
Write-Host "NOTA: Linked PRs y Sub-issues progress son columnas del sistema, no escribibles via API."
