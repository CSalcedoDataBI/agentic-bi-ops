<#
.SYNOPSIS
    Turn a plan into a tracked epic + native sub-issues on the repo board (/board plan).

.DESCRIPTION
    A plan is not done when the markdown is written - a plan is done when it
    is a trackable epic with sub-issues on the board. This script is the
    deterministic half of /board plan (the agent gathers/parses the plan and
    confirms with the user; this script creates everything):

      1. Ensures the 'plan' and 'plan-task' labels exist.
      2. Creates the EPIC issue (label: plan) with the description and a
         task overview.
      3. Reuses Board-Breakdown.ps1 to create one child issue per task
         (label: plan-task) attached as NATIVE sub-issues - the board's
         Sub-issues progress column fills itself as they close.
      4. Resolves the repo's board with Resolve-Board.ps1 (find-or-reuse,
         NEVER a blind duplicate) and adds epic + children to it.

    The created issues enter the normal work flow: /board work -> branch ->
    PR with Closes # -> review gate -> merge.

.PARAMETER Title
    Epic title (e.g. "plan: migrate reports to PBIR"). Mandatory.

.PARAMETER Tasks
    One or more SUBSTANTIAL task titles (tiny steps belong as checkboxes in
    -Description, not as issues). Mandatory.

.PARAMETER Description
    Epic body text: goal, context, links (full blob URLs on PUSHED refs
    only - relative paths render broken in issues).

.PARAMETER Repo
    owner/name. Default: derived from the current directory's origin remote.

.PARAMETER Owner
    Board owner. Default: the owner part of -Repo.

.PARAMETER ProjectNum
    Board number. Default: resolved via Resolve-Board.ps1 (no duplicate
    creation; warns if the repo has no board yet).

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Defaults to GITHUB_TOKEN_PERSONAL.

.EXAMPLE
    .\Board-Plan.ps1 -Title "plan: PBIR migration" -Tasks "inventory reports", "convert themes", "validate rendering" -Description "Goal: ..."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string[]]$Tasks,
    [string]$Description = "",
    [string]$Repo = "",
    [string]$Owner = "",
    [int]   $ProjectNum = 0,
    [string]$TokenVar = "GITHUB_TOKEN_PERSONAL"
)

$ErrorActionPreference = "Stop"

if (-not $env:GH_TOKEN) {
    $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User")
}
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

if (-not $Repo) {
    $originUrl = git remote get-url origin 2>$null
    if ($originUrl -match 'github\.com[/:]([^/]+)/([^/.]+)') { $Repo = "$($Matches[1])/$($Matches[2])" }
}
if (-not $Repo) { throw "No pude derivar el repo del origin - pasa -Repo owner/name." }
if (-not $Owner) { $Owner = ($Repo -split "/")[0] }

Write-Host "=== Board-Plan  '$Title'  ($($Tasks.Count) tareas)  ->  $Repo ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Labels ──────────────────────────────────────────────────────────────────
gh label create plan      --color 0E8A16 --description "Tracked plan epic"          --force --repo $Repo 2>&1 | Out-Null
gh label create plan-task --color C2E0C6 --description "Child task of a tracked plan" --force --repo $Repo 2>&1 | Out-Null

# ── 2. Epic ────────────────────────────────────────────────────────────────────
$taskOverview = ($Tasks | ForEach-Object { "- $_" }) -join "`n"
$body = ""
if ($Description) { $body += "$Description`n`n" }
$body += "## Tasks (native sub-issues)`n$taskOverview`n`nCreated by /board plan - work them with /board work."

$epicUrl = $body | gh issue create --repo $Repo --title $Title --label plan --body-file -
$epicNum = [int]($epicUrl -split '/')[-1]
Write-Host "  OK  Epic #$epicNum  $Title" -ForegroundColor Green
Write-Host "      $epicUrl" -ForegroundColor DarkCyan

# ── 3. Children as native sub-issues (reuse Board-Breakdown) ──────────────────
& (Join-Path $PSScriptRoot "Board-Breakdown.ps1") -Parent $epicNum -Tasks $Tasks -Repo $Repo -Label "plan-task"

# ── 4. Board: resolve (never duplicate) and register ──────────────────────────
if ($ProjectNum -le 0) {
    $resolved = & (Join-Path $PSScriptRoot "Resolve-Board.ps1") -Owner $Owner -Repo $Repo -CreateIfMissing:$false
    if ($resolved) { $ProjectNum = [int]$resolved }
}
if ($ProjectNum -gt 0) {
    $boardUrl = "https://github.com/users/$Owner/projects/$ProjectNum"
    gh project item-add $ProjectNum --owner $Owner --url $epicUrl 2>&1 | Out-Null
    # Children too (best-effort - auto-add CI may already cover them)
    $subs = gh api graphql -f query='
query($o:String!, $r:String!, $n:Int!) {
  repository(owner:$o, name:$r) {
    issue(number:$n) { subIssues(first:50) { nodes { number url } } }
  }
}' -f "o=$(($Repo -split '/')[0])" -f "r=$(($Repo -split '/')[1])" -F "n=$epicNum" | ConvertFrom-Json
    foreach ($s in @($subs.data.repository.issue.subIssues.nodes)) {
        gh project item-add $ProjectNum --owner $Owner --url $s.url 2>&1 | Out-Null
    }
    Write-Host ""
    Write-Host "  OK  Epic + sub-issues registrados en el board #$ProjectNum" -ForegroundColor Green
    Write-Host ""
    Write-Host "Siguiente: /board fill (Priority/Size/Type) y /board work para empezar la primera tarea." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "  WARN $Repo no tiene board vinculado - crea uno con /board init y agrega el epic con /board add $epicUrl" -ForegroundColor DarkYellow
}
