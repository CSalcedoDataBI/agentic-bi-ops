<#
.SYNOPSIS
    Detect and fill gaps in a GitHub Projects v2 board.

.DESCRIPTION
    Reads all items from a GitHub Projects v2 board and detects gaps:
    missing assignees, Status, Priority, Size, and Type. Then fills them.

    Fill rules:
      Assignees : if empty, assign the board owner
      Status    : issue CLOSED -> Done
                  issue OPEN + merged PR -> Done
                  issue OPEN + open PR   -> In Progress
                  issue OPEN + no PR     -> Todo
      Priority  : if empty -> P2 Medium
      Size      : if empty -> M
      Type      : if empty -> detect from labels (bug->Bug, docs->Docs,
                  refactor->Refactor, chore->Chore), else Feature

    Linked PRs and Sub-issues progress are system-derived — not writable via API.

.PARAMETER Owner
    GitHub username that owns the project board. Defaults to CSalcedoDataBI.

.PARAMETER Repo
    owner/repo string. Used for issue assignment calls.

.PARAMETER ProjectNum
    GitHub Projects v2 number (e.g. 1).

.PARAMETER DryRun
    Print the plan without executing any changes.

.PARAMETER Auto
    Execute changes without asking for confirmation.

.EXAMPLE
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/csalcedodatabi.com -ProjectNum 1 -DryRun
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/csalcedodatabi.com -ProjectNum 1
    .\Board-Fill.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/csalcedodatabi.com -ProjectNum 1 -Auto
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

$projectId = $projData.data.user.projectV2.id
$allFields = $projData.data.user.projectV2.fields.nodes | Where-Object { $_.name }

function Get-Field($name) { $allFields | Where-Object { $_.name -eq $name } }
function Get-Opt($field, $optName) { ($field.options | Where-Object { $_.name -eq $optName }).id }

$statusNode = Get-Field "Status"
$statusId   = $statusNode.id
$doneId     = Get-Opt $statusNode "Done"
$inProgId   = Get-Opt $statusNode "In Progress"
$todoId     = Get-Opt $statusNode "Todo"

$prioNode   = Get-Field "Priority"
$prioId     = $prioNode.id
$prioMedId  = Get-Opt $prioNode "P2 Medium"

$sizeNode   = Get-Field "Size"
$sizeId     = $sizeNode.id
$sizeMId    = Get-Opt $sizeNode "M"

$typeNode   = Get-Field "Type"
$typeId     = $typeNode.id

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
              labels(first:10) { nodes { name } }
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

    $fv = $item.fieldValues.nodes
    $assigneeCount  = $c.assignees.nodes.Count
    $currentStatus  = ($fv | Where-Object { $_.field.name -eq "Status" }).optionId
    $currentPrio    = ($fv | Where-Object { $_.field.name -eq "Priority" }).optionId
    $currentSize    = ($fv | Where-Object { $_.field.name -eq "Size" }).optionId
    $currentType    = ($fv | Where-Object { $_.field.name -eq "Type" }).optionId
    $currentStatusN = ($fv | Where-Object { $_.field.name -eq "Status" }).name

    $mergedPRs = @($c.timelineItems.nodes.source | Where-Object { $_.merged -eq $true })
    $openPRs   = @($c.timelineItems.nodes.source | Where-Object { $_.state  -eq "OPEN"  })
    $labels    = @($c.labels.nodes.name | Where-Object { $_ } | ForEach-Object { $_.ToLower() })

    $changes = @()

    # Assignee
    if ($assigneeCount -eq 0) {
        $changes += [PSCustomObject]@{ Type="assignee"; Display="Assignee vacio -> $Owner" }
    }

    # Status
    $targetStatus = $null; $targetStatusN = $null
    if     ($c.state -eq "CLOSED"  -and $currentStatus -ne $doneId)  { $targetStatus=$doneId;   $targetStatusN="Done (issue cerrado)" }
    elseif ($mergedPRs.Count -gt 0 -and $currentStatus -ne $doneId)  { $targetStatus=$doneId;   $targetStatusN="Done (PR mergeado)" }
    elseif ($openPRs.Count   -gt 0 -and $currentStatus -eq $todoId)  { $targetStatus=$inProgId; $targetStatusN="In Progress (PR abierto)" }
    elseif (-not $currentStatus)                                       { $targetStatus=$todoId;   $targetStatusN="Todo (sin PR)" }
    if ($targetStatus) {
        $changes += [PSCustomObject]@{ Type="single"; FieldId=$statusId; TargetId=$targetStatus; Display="Status [$currentStatusN] -> $targetStatusN" }
    }

    # Priority
    if (-not $currentPrio -and $prioMedId) {
        $changes += [PSCustomObject]@{ Type="single"; FieldId=$prioId; TargetId=$prioMedId; Display="Priority vacio -> P2 Medium" }
    }

    # Size
    if (-not $currentSize -and $sizeMId) {
        $changes += [PSCustomObject]@{ Type="single"; FieldId=$sizeId; TargetId=$sizeMId; Display="Size vacio -> M" }
    }

    # Type — detect from labels, fallback to Feature
    if (-not $currentType -and $typeId) {
        $detectedType = "Feature"
        if     ($labels -contains "bug")      { $detectedType = "Bug" }
        elseif ($labels -contains "docs")     { $detectedType = "Docs" }
        elseif ($labels -contains "refactor") { $detectedType = "Refactor" }
        elseif ($labels -contains "chore")    { $detectedType = "Chore" }
        $typeOptId = Get-Opt $typeNode $detectedType
        if ($typeOptId) {
            $changes += [PSCustomObject]@{ Type="single"; FieldId=$typeId; TargetId=$typeOptId; Display="Type vacio -> $detectedType" }
        }
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
            elseif ($ch.Type -eq "single") {
                $itemId  = $entry.ItemId
                $fieldId = $ch.FieldId
                $optId   = $ch.TargetId
                gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -F "proj=$projectId" -F "item=$itemId" -F "field=$fieldId" -F "opt=$optId" | Out-Null
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
