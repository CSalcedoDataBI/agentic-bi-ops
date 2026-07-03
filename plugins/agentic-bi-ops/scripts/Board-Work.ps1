<#
.SYNOPSIS
    Show pending work across boards and start working an issue (single or parallel).

.DESCRIPTION
    Modes, designed for the /board work flow:

      1. -ListBoards [-Repo <owner/name>]
         Lists boards with their pending count (items in Backlog or no Status),
         so the user can pick which board to work from. Without -Repo it
         lists EVERY board of the owner (backups excluded); with -Repo it
         lists only the boards LINKED to that repository (repository.projectsV2),
         which is the "current repo" scope of the /board work flow.

      2. -ProjectNum <n>
         Lists the PENDING items of that board (Status = Backlog or empty),
         sorted by Priority (P0 first, empty last), with issue number, title,
         Priority, Size and Type. Draft notes are flagged (convert them with
         /board fill before starting them).

      3. -ProjectNum <n> -Start <issueNum>
         Starts working that issue: moves the board item to "In Progress",
         assigns the owner, and prints the full issue context (labels,
         body, sub-issues) so the agent can begin working it in-session.
         Supports -DryRun to preview without mutating.

      5. -ProjectNum <n> -Parallel <issueNums>
         Batch-start SEVERAL independent issues at once. For each issue it
         runs the same start logic as mode 3 (In Progress + assign + claim)
         but ALWAYS in its own isolated git worktree (../<repo>--issue-<n>),
         each branched off a fresh origin/main. Add -Launch to open one visible
         Claude session per worktree (a Windows Terminal tab when 'wt' exists,
         else a standalone pwsh window), each briefed to work its own issue
         end-to-end. -DryRun plans the whole batch (and previews the launch
         commands) without mutating the board, touching git, or spawning
         anything. Blocked / claimed / closed issues are skipped with a reason,
         never aborting the batch.

    Same conventions as Board-Fill.ps1: token from the Windows USER registry
    (unless GH_TOKEN is already set by gh-account), pure-ASCII source, and
    the board URL always printed at the end.

.PARAMETER Owner
    GitHub username that owns the boards. Defaults to CSalcedoDataBI.

.PARAMETER ListBoards
    Mode 1: list boards with pending counts (all of the owner, or only the
    ones linked to -Repo when given).

.PARAMETER Repo
    owner/name. With -ListBoards: restrict the listing to boards linked to
    this repository (the current-repo scope).

.PARAMETER ProjectNum
    GitHub Projects v2 number. Mode 2 alone, mode 3 with -Start.

.PARAMETER Start
    Issue number to start working (requires -ProjectNum).

.PARAMETER Parallel
    One or more issue numbers to batch-start, each in its own worktree
    (requires -ProjectNum). Mutually exclusive with -Start / -ToReview.

.PARAMETER Launch
    With -Parallel: after starting each worktree, spawn one visible Claude
    session per worktree (Windows Terminal tab, or a pwsh window as fallback),
    each briefed to work its own issue to a PR + review gate. With -DryRun it
    only previews the launch commands.

.PARAMETER ToReview
    Issue number to move into the "In Review" Status column (requires
    -ProjectNum). The work flow calls this after opening the PR: the change is
    now in review / testing while the gate runs. Errors if the board has no
    "In Review" option.

.PARAMETER DryRun
    With -Start / -Parallel / -ToReview: print what would change without executing.

.PARAMETER Branch
    With -Start: also create and checkout a work branch issue-<num>-<slug>
    (only when the current directory is a clone of the issue's repo).
    Finishing the work MUST then go through a PR with "Closes #<num>" so
    GitHub fills the Linked pull requests column on the board by itself.
    -Parallel always creates a branch (in a worktree), so -Branch is implied there.

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Defaults to GITHUB_TOKEN_PERSONAL;
    use GITHUB_TOKEN_BUSINESS for the PAL-Devs account.

.EXAMPLE
    .\Board-Work.ps1 -ListBoards
    .\Board-Work.ps1 -ListBoards -Repo CSalcedoDataBI/agentic-bi-ops
    .\Board-Work.ps1 -ProjectNum 13
    .\Board-Work.ps1 -ProjectNum 13 -Start 12 -DryRun
    .\Board-Work.ps1 -ProjectNum 13 -Start 12 -Branch
    .\Board-Work.ps1 -ProjectNum 13 -Parallel 12,14,15 -DryRun
    .\Board-Work.ps1 -ProjectNum 13 -Parallel 12,14,15
    .\Board-Work.ps1 -ProjectNum 13 -Parallel 12,14,15 -Launch
    .\Board-Work.ps1 -ProjectNum 13 -Parallel 12,14,15 -Launch -DryRun
    .\Board-Work.ps1 -ProjectNum 13 -ToReview 12
#>
[CmdletBinding()]
param(
    [string]$Owner    = "CSalcedoDataBI",
    [switch]$ListBoards,
    [string]$Repo     = "",
    [int]   $ProjectNum = 0,
    [int]   $Start      = 0,
    [int[]] $Parallel   = @(),
    [switch]$Launch,
    [int]   $ToReview   = 0,
    [switch]$DryRun,
    [switch]$Branch,
    [switch]$IgnoreBlocked,
    [switch]$TakeOver,
    [string]$TokenVar   = "GITHUB_TOKEN_PERSONAL"
)

$ErrorActionPreference = "Stop"

# -- 0. Token (respect GH_TOKEN if gh-account already set it) ------------------
if (-not $env:GH_TOKEN) {
    $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User")
}
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

function Get-BoardUrl([int]$num) { "https://github.com/users/$Owner/projects/$num" }

# An item is PENDING when its Status is Backlog or it has no Status yet.
function Test-Pending($item) {
    (-not $item.status) -or ($item.status -eq "Backlog")
}

# -- Local session registry (multi-session awareness) ---------------------------
# Shared across worktrees of the same repo: it lives next to the MAIN clone's .git
# (git rev-parse --git-common-dir), inside .agentic-bi-ops/ (gitignored).
# Session identity = the PARENT process of this script (the long-lived Claude/host
# process), because the script's own PID dies as soon as it returns.
# The shared .agentic-bi-ops/ dir (registry + briefings) lives next to the MAIN
# clone's .git so every worktree of the repo sees the same one.
function Get-AbiosDir {
    $common = git rev-parse --git-common-dir 2>$null
    if (-not $common) { return $null }
    try { $root = Split-Path (Resolve-Path $common).Path -Parent } catch { return $null }
    $dir = Join-Path $root ".agentic-bi-ops"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    return $dir
}

function Get-SessionRegistryPath {
    $dir = Get-AbiosDir
    if (-not $dir) { return $null }
    return (Join-Path $dir "sessions.json")
}

function Read-SessionRegistry {
    $p = Get-SessionRegistryPath
    if (-not $p -or -not (Test-Path $p)) { return @() }
    try { $entries = @(Get-Content $p -Raw | ConvertFrom-Json) } catch { return @() }
    # Stale cleanup: drop entries whose session process is dead
    $alive = @($entries | Where-Object { $_.sessionPid -and (Get-Process -Id $_.sessionPid -ErrorAction SilentlyContinue) })
    if ($alive.Count -ne $entries.Count) {
        # Pipe (not -InputObject) or a passed array gets double-wrapped by -AsArray
        $alive | ConvertTo-Json -Depth 4 -AsArray | Set-Content $p
    }
    return $alive
}

function Write-SessionRegistryEntry([int]$issueNum, [string]$branch, [string]$workPath) {
    $p = Get-SessionRegistryPath
    if (-not $p) { return }
    $parentPid = $null
    try { $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId } catch { }
    if (-not $parentPid) { return }
    $entries = @(Read-SessionRegistry | Where-Object { $_.issue -ne $issueNum })
    $entries += [PSCustomObject]@{
        issue      = $issueNum
        branch     = $branch
        workPath   = $workPath
        sessionPid = $parentPid
        host       = $env:COMPUTERNAME
        started    = (Get-Date -Format "yyyy-MM-dd HH:mm")
    }
    $entries | ConvertTo-Json -Depth 4 -AsArray | Set-Content $p
}

# ==============================================================================
# Reusable start helpers (shared by -Start mode 3 and -Parallel mode 5)
# ==============================================================================

# Work branch name: issue-<num>-<slug-from-title>. Pure -> unit-testable.
function Get-IssueSlugBranch([int]$num, [string]$title) {
    $slug = ($title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 40) {
        $slug = $slug.Substring(0, 40)
        if ($slug.Contains('-')) { $slug = $slug.Substring(0, $slug.LastIndexOf('-')) }  # no cortar palabras
        $slug = $slug.Trim('-')
    }
    return "issue-$num-$slug"
}

# Resolve the board id + Status field + "In Progress" option once, reuse per issue.
function Resolve-BoardStatus([string]$owner, [int]$projectNum) {
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
}' -F "owner=$owner" -F "num=$projectNum" | ConvertFrom-Json

    $projectId  = $projData.data.user.projectV2.id
    if (-not $projectId) { throw "Board #$projectNum no encontrado para $owner." }
    $statusNode = $projData.data.user.projectV2.fields.nodes | Where-Object { $_.name -eq "Status" }
    $inProgId   = ($statusNode.options | Where-Object { $_.name -eq "In Progress" }).id
    if (-not $inProgId) { throw "El board #$projectNum no tiene la opcion 'In Progress' en Status." }
    return [PSCustomObject]@{ projectId = $projectId; statusNode = $statusNode; inProgId = $inProgId }
}

# Find the board item for an issue number, with one retry (eventual consistency).
function Get-BoardItem([string]$projectId, [int]$issueNum) {
    foreach ($attempt in 1..2) {
        $itemsData = gh api graphql -f query='
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
                name
              }
            }
          }
          content {
            __typename
            ... on Issue {
              number title state url
              assignees(first:5) { nodes { login } }
              repository { nameWithOwner }
            }
          }
        }
      }
    }
  }
}' -F "proj=$projectId" | ConvertFrom-Json

        $item = $itemsData.data.node.items.nodes |
                Where-Object { $_.content.__typename -eq "Issue" -and $_.content.number -eq $issueNum } |
                Select-Object -First 1
        if ($item) { return $item }
        if ($attempt -eq 1) {
            Write-Host "  (issue #$issueNum aun no visible en el board - reintentando en 4s...)" -ForegroundColor DarkGray
            Start-Sleep -Seconds 4
        }
    }
    return $null
}

# Return the list of reasons this issue is blocked (empty array => not blocked).
function Get-IssueBlockers([string]$repo, [int]$issueNum) {
    $blockers = @()
    try {
        $issueLabels = @((gh issue view $issueNum --repo $repo --json labels | ConvertFrom-Json).labels.name)
        if ($issueLabels -contains "blocked") { $blockers += "label 'blocked' presente" }
    } catch { }
    # Native blocked-by dependencies (best-effort: API may not exist for the account)
    try {
        $deps = gh api "repos/$repo/issues/$issueNum/dependencies/blocked_by" 2>$null | ConvertFrom-Json
        foreach ($d in @($deps | Where-Object { $_.state -eq "open" })) {
            $blockers += "bloqueado por #$($d.number) '$($d.title)' (abierto)"
        }
    } catch { }
    return $blockers
}

# Create an isolated worktree ../<repo>--issue-<n> for a branch. Returns the path
# or $null. $baseRef (e.g. origin/main) is used only when creating a NEW branch:
# parallel starts each independent issue off a fresh main; single start passes ""
# to keep branching off the current HEAD.
function New-IssueWorktree([string]$repo, [int]$issueNum, [string]$branchName, [string]$baseRef = "") {
    $repoName = ($repo -split '/')[1]
    $wtPath   = Join-Path (Split-Path (Get-Location) -Parent) "$repoName--issue-$issueNum"
    # Reuse: is the branch already checked out in some worktree?
    $wtList = git worktree list --porcelain 2>$null | Out-String
    if ($wtList -match "(?m)^worktree (.+)\r?\n(?:.*\r?\n)?branch refs/heads/$([regex]::Escape($branchName))") {
        $existingPath = $Matches[1]
        Write-Host "  OK  Worktree ya existia para la rama: $existingPath" -ForegroundColor Green
        Write-Host "       TRABAJA EL ISSUE ALLI: cd `"$existingPath`"" -ForegroundColor Cyan
        return $existingPath
    }
    if (Test-Path $wtPath) {
        Write-Host "  WARN la carpeta $wtPath existe pero no es worktree de $branchName - resuelvelo manualmente." -ForegroundColor DarkYellow
        return $null
    }
    git rev-parse --verify --quiet $branchName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0)     { git worktree add $wtPath $branchName 2>&1 | Out-Null }
    elseif ($baseRef)            { git worktree add $wtPath -b $branchName $baseRef 2>&1 | Out-Null }
    else                         { git worktree add $wtPath -b $branchName 2>&1 | Out-Null }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK  Worktree creado: $wtPath (rama $branchName)" -ForegroundColor Green
        Write-Host "       TRABAJA EL ISSUE ALLI: cd `"$wtPath`"" -ForegroundColor Cyan
        Write-Host "       Al mergear el PR, limpia con: git worktree remove `"$wtPath`"" -ForegroundColor DarkGray
        return $wtPath
    }
    Write-Host "  FAIL no se pudo crear el worktree para #$issueNum - crea la rama manualmente: git checkout -b $branchName" -ForegroundColor Red
    return $null
}

# Start ONE issue: find item, run safety checks, and (unless -DryRunStart) move it
# to In Progress + assign + claim + optionally branch/worktree. Writes progress and
# returns a structured result so callers (single or batch) can decide what to print
# and how to exit. -PreferWorktree forces an isolated worktree (batch); otherwise the
# in-place-vs-worktree decision matches the classic single-start behaviour.
function Invoke-IssueStart {
    param(
        [int]    $IssueNum,
        [object] $Ctx,
        [string] $Owner,
        [switch] $MakeBranch,
        [switch] $PreferWorktree,
        [string] $BaseRef = "",
        [switch] $DryRunStart,
        [switch] $IgnoreBlocked,
        [switch] $TakeOver
    )
    $result = [PSCustomObject]@{
        issue = $IssueNum; title = ""; repo = ""; branch = ""; workPath = ""
        started = $false; dryRun = [bool]$DryRunStart; skipped = ""
    }

    $item = Get-BoardItem $Ctx.projectId $IssueNum
    if (-not $item) {
        $result.skipped = "no esta en el board (agregalo con /board add)"
        Write-Host "  SKIP #${IssueNum}: $($result.skipped)" -ForegroundColor DarkYellow
        return $result
    }

    $result.title = $item.content.title
    $repo         = $item.content.repository.nameWithOwner
    $result.repo  = $repo
    $currentStatus = ($item.fieldValues.nodes | Where-Object { $_.field.name -eq "Status" }).name
    if (-not $currentStatus) { $currentStatus = "(vacio)" }

    if ($item.content.state -eq "CLOSED") {
        $result.skipped = "CERRADO (reabre con gh issue reopen $IssueNum --repo $repo)"
        Write-Host "  SKIP #${IssueNum}: $($result.skipped)" -ForegroundColor Red
        return $result
    }

    if (-not $IgnoreBlocked) {
        $blockers = @(Get-IssueBlockers $repo $IssueNum)
        if ($blockers.Count -gt 0) {
            $result.skipped = "BLOQUEADO: " + ($blockers -join "; ")
            Write-Host "  SKIP #${IssueNum}: bloqueado (usa -IgnoreBlocked si es falso positivo):" -ForegroundColor Red
            $blockers | ForEach-Object { Write-Host "         - $_" -ForegroundColor Red }
            return $result
        }
    }

    $assignees = @($item.content.assignees.nodes.login)
    if (-not $TakeOver -and $currentStatus -eq "In Progress" -and $assignees.Count -gt 0) {
        $result.skipped = "OCUPADO (In Progress, asignado a $($assignees -join ', '))"
        Write-Host "  SKIP #${IssueNum}: $($result.skipped) - otra sesion probablemente lo trabaja." -ForegroundColor Red
        $lastClaim = gh api "repos/$repo/issues/$IssueNum/comments" --jq '[.[] | select(.body | startswith("[abios-claim]"))] | last | .body' 2>$null
        if ($lastClaim -and $lastClaim -ne "null") { Write-Host "         Ultimo claim: $lastClaim" -ForegroundColor Yellow }
        Write-Host "         Re-ejecuta con -TakeOver si la sesion esta muerta o quieres retomarlo." -ForegroundColor Yellow
        return $result
    }

    $branchName    = Get-IssueSlugBranch $IssueNum $item.content.title
    $result.branch = $branchName

    Write-Host ("  #{0} {1}" -f $IssueNum, $item.content.title) -ForegroundColor Yellow
    Write-Host ("       Repo: {0} | Status actual: {1} -> In Progress | Assignee -> {2}" -f $repo, $currentStatus, $Owner) -ForegroundColor DarkGray
    if ($MakeBranch) { Write-Host "       Rama de trabajo: $branchName" -ForegroundColor DarkGray }

    if ($DryRunStart) {
        Write-Host "  #${IssueNum}: DRY-RUN - nada ejecutado." -ForegroundColor Gray
        return $result
    }

    # -- Execute: Status -> In Progress -----------------------------------------
    gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -f "proj=$($Ctx.projectId)" -f "item=$($item.id)" -f "field=$($Ctx.statusNode.id)" -f "opt=$($Ctx.inProgId)" | Out-Null
    Write-Host "  OK  Status -> In Progress" -ForegroundColor Green

    # -- Execute: assign owner --------------------------------------------------
    try {
        gh api "repos/$repo/issues/$IssueNum/assignees" -X POST -F "assignees[]=$Owner" | Out-Null
        Write-Host "  OK  Assignee -> $Owner" -ForegroundColor Green
    } catch {
        Write-Host "  WARN no se pudo asignar: $_" -ForegroundColor DarkYellow
    }

    # -- Execute: claim fingerprint (multi-session diagnostics) -----------------
    $claimNote = if ($TakeOver) { "TAKEOVER" } else { "claim" }
    $fingerprint = "[abios-claim] $claimNote por sesion Claude en $env:COMPUTERNAME (PID $PID) - $(Get-Date -Format 'yyyy-MM-dd HH:mm') - rama $branchName"
    try {
        gh issue comment $IssueNum --repo $repo --body $fingerprint | Out-Null
        Write-Host "  OK  Claim registrado ($claimNote)" -ForegroundColor Green
    } catch {
        Write-Host "  WARN no se pudo registrar el claim: $_" -ForegroundColor DarkYellow
    }

    # -- Execute: work branch (only if cwd is a clone of the issue's repo) -------
    if ($MakeBranch) {
        $originUrl = ""
        try { $originUrl = (git remote get-url origin 2>$null) } catch { }
        if ($originUrl -notmatch [regex]::Escape($repo)) {
            Write-Host "  WARN el directorio actual no es un clon de $repo - rama NO creada." -ForegroundColor DarkYellow
            Write-Host "       Crea la rama en ese repo con: git checkout -b $branchName" -ForegroundColor DarkYellow
        } else {
            $dirty     = @(git status --porcelain 2>$null)
            $curBranch = git branch --show-current 2>$null
            # Batch (-PreferWorktree) always isolates. Single start keeps the classic
            # dirty-tree / other-issue-branch guard: never switch a busy working copy.
            $needWorktree = $PreferWorktree -or `
                            ($dirty.Count -gt 0 -and $curBranch -ne $branchName) -or `
                            ($curBranch -and $curBranch -match '^issue-\d+' -and $curBranch -ne $branchName)
            if ($needWorktree) {
                if (-not $PreferWorktree) {
                    Write-Host "  OCUPADO: working tree ocupado (rama actual: $curBranch) - uso un worktree aislado:" -ForegroundColor Yellow
                }
                $result.workPath = New-IssueWorktree $repo $IssueNum $branchName $BaseRef
            } else {
                git rev-parse --verify --quiet $branchName 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    git checkout $branchName 2>&1 | Out-Null
                    Write-Host "  OK  Rama $branchName ya existia - checkout hecho" -ForegroundColor Green
                } else {
                    git checkout -b $branchName 2>&1 | Out-Null
                    Write-Host "  OK  Rama $branchName creada y activa" -ForegroundColor Green
                }
                $result.workPath = (Get-Location).Path
            }
        }
        if ($result.workPath) {
            Write-SessionRegistryEntry -issueNum $IssueNum -branch $branchName -workPath $result.workPath
            Write-Host "  OK  Sesion registrada en .agentic-bi-ops/sessions.json" -ForegroundColor Green
        }
    }

    $result.started = $true
    return $result
}

# Print the full issue context so an in-session agent can start working (mode 3).
function Write-IssueContext([int]$issueNum, [string]$repo) {
    $issue = gh issue view $issueNum --repo $repo --json title,body,labels,milestone,url,state | ConvertFrom-Json
    Write-Host "----- CONTEXTO DEL ISSUE -----" -ForegroundColor Cyan
    Write-Host ("Titulo : {0}" -f $issue.title)
    Write-Host ("URL    : {0}" -f $issue.url)
    $labelNames = @($issue.labels | ForEach-Object { $_.name })
    if ($labelNames.Count -gt 0) { Write-Host ("Labels : {0}" -f ($labelNames -join ", ")) }
    if ($issue.milestone)        { Write-Host ("Hito   : {0}" -f $issue.milestone.title) }
    Write-Host ""
    if ($issue.body) { Write-Host $issue.body } else { Write-Host "(sin descripcion)" -ForegroundColor DarkGray }
    Write-Host ""
    try {
        $repoParts = $repo -split "/"
        $subData = gh api graphql -f query='
query($o:String!, $r:String!, $n:Int!) {
  repository(owner:$o, name:$r) {
    issue(number:$n) {
      subIssues(first:30) { nodes { number title state } }
    }
  }
}' -F "o=$($repoParts[0])" -F "r=$($repoParts[1])" -F "n=$issueNum" 2>$null | ConvertFrom-Json
        $subs = @($subData.data.repository.issue.subIssues.nodes)
        if ($subs.Count -gt 0) {
            Write-Host "Sub-issues:" -ForegroundColor Cyan
            foreach ($s in $subs) { Write-Host ("  #{0} [{1}] {2}" -f $s.number, $s.state, $s.title) }
            Write-Host ""
        }
    } catch { }
    Write-Host "------------------------------" -ForegroundColor Cyan
}

# ==============================================================================
# Parallel session launcher (mode 5 -Launch): one visible Claude session per
# worktree, each briefed to work its own issue end-to-end.
# ==============================================================================

# The one-line first message a spawned Claude session receives. Pure -> testable.
function Get-SessionBriefing([int]$issueNum, [string]$repo, [string]$branch, [string]$workPath) {
    return ("Pick up GitHub issue #$issueNum in $repo. It is already In Progress and claimed, " +
            "on branch $branch in this worktree ($workPath). Steps: " +
            "(1) read it with: gh issue view $issueNum --repo $repo ; " +
            "(2) implement it fully in this worktree; " +
            "(3) open the PR with: plugins/agentic-bi-ops/scripts/New-BoardPR.ps1 -Issue $issueNum ; " +
            "(4) pass the review gate with Board-ReviewGate.ps1, address feedback, then squash-merge. " +
            "Work ONLY this issue - do not touch other worktrees or issues.")
}

# Build the exact launch command for a worktree session. Returns an object
# { launcher, args, briefingFile } WITHOUT spawning - pure enough to unit-test
# and to preview under -DryRun. Windows Terminal tab when 'wt' exists (grouped in
# a named window), else a standalone pwsh window. The briefing is passed via a
# file (written by the caller) so no long/quoted text ever hits the command line.
function Build-WorktreeLaunch([int]$issueNum, [string]$workPath, [string]$briefingFile, [string]$windowName = "abios-parallel") {
    $tabTitle  = "issue-$issueNum"
    $claudeCmd = "claude (Get-Content -Raw -LiteralPath '$briefingFile')"
    if (Get-Command wt -ErrorAction SilentlyContinue) {
        return [PSCustomObject]@{
            launcher     = "wt"
            args         = @('-w', $windowName, 'new-tab', '--title', $tabTitle,
                             '--startingDirectory', $workPath, 'pwsh', '-NoExit', '-Command', $claudeCmd)
            briefingFile = $briefingFile
            usesWt       = $true
        }
    }
    return [PSCustomObject]@{
        launcher     = "pwsh"
        args         = @('-NoExit', '-Command', $claudeCmd)
        briefingFile = $briefingFile
        usesWt       = $false
    }
}

# Spawn (or -Preview) ONE visible Claude session for a started worktree.
function Start-WorktreeSession {
    param(
        [int]$IssueNum, [string]$Repo, [string]$Branch, [string]$WorkPath,
        [switch]$Preview
    )
    $abios = Get-AbiosDir
    $briefingFile = if ($abios) { Join-Path $abios "briefing-$IssueNum.txt" } else { Join-Path $WorkPath "briefing-$IssueNum.txt" }
    $plan  = Build-WorktreeLaunch $IssueNum $WorkPath $briefingFile

    if ($Preview) {
        Write-Host ("  [preview] #{0}: {1} {2}" -f $IssueNum, $plan.launcher, ($plan.args -join ' ')) -ForegroundColor Gray
        return $plan
    }

    if (-not $WorkPath -or -not (Test-Path $WorkPath)) {
        Write-Host "  WARN #${IssueNum}: worktree '$WorkPath' no existe - no se lanza sesion." -ForegroundColor DarkYellow
        return $null
    }
    # Persist the briefing so the spawned session reads it without command-line quoting.
    Set-Content -LiteralPath $briefingFile -Value (Get-SessionBriefing $IssueNum $Repo $Branch $WorkPath) -Encoding UTF8
    try {
        if ($plan.usesWt) { Start-Process $plan.launcher -ArgumentList $plan.args | Out-Null }
        else              { Start-Process $plan.launcher -ArgumentList $plan.args -WorkingDirectory $WorkPath | Out-Null }
        $how = if ($plan.usesWt) { "WT tab 'issue-$IssueNum'" } else { "ventana pwsh" }
        Write-Host ("  OK  #{0}: sesion Claude lanzada ({1}) en {2}" -f $IssueNum, $how, $WorkPath) -ForegroundColor Green
    } catch {
        Write-Host "  FAIL #${IssueNum}: no se pudo lanzar la sesion: $_" -ForegroundColor Red
    }
    return $plan
}

# ==============================================================================
# MODE 1: -ListBoards  -> every board with its pending count
# ==============================================================================
if ($ListBoards) {
    if ($Repo) {
        # Current-repo scope: only boards LINKED to this repository
        Write-Host "=== Boards vinculados a $Repo (contando pendientes) ===" -ForegroundColor Cyan
        Write-Host ""
        $rp = $Repo -split "/"
        $linked = gh api graphql -f query='
query($o:String!, $r:String!) {
  repository(owner:$o, name:$r) {
    projectsV2(first:20) {
      nodes {
        number title closed
        owner { ... on User { login } ... on Organization { login } }
      }
    }
  }
}' -f "o=$($rp[0])" -f "r=$($rp[1])" | ConvertFrom-Json
        $boards = @($linked.data.repository.projectsV2.nodes |
                    Where-Object { -not $_.closed -and $_.title -notmatch '(?i)backup' } |
                    ForEach-Object { [PSCustomObject]@{ number = $_.number; title = $_.title; ownerLogin = $_.owner.login } })
        if ($boards.Count -eq 0) {
            Write-Host "El repo $Repo no tiene boards vinculados. Crea/vincula uno con /board init." -ForegroundColor Yellow
            exit 0
        }
    } else {
        # Account scope: every board of the owner
        Write-Host "=== Boards de $Owner (contando pendientes, puede tardar unos segundos) ===" -ForegroundColor Cyan
        Write-Host ""
        $projects = (gh project list --owner $Owner --format json --limit 30 | ConvertFrom-Json).projects
        $boards   = @($projects | Where-Object { $_.title -notmatch '(?i)backup' } |
                      ForEach-Object { [PSCustomObject]@{ number = $_.number; title = $_.title; ownerLogin = $Owner } })
        if ($boards.Count -eq 0) { Write-Host "No hay boards para $Owner."; exit 0 }
    }

    $rows = @()
    foreach ($b in $boards) {
        try {
            $items   = (gh project item-list $b.number --owner $b.ownerLogin --format json --limit 200 | ConvertFrom-Json).items
            $pending = @($items | Where-Object { Test-Pending $_ }).Count
            $total   = @($items).Count
        } catch {
            $pending = "?"; $total = "?"
        }
        $rows += [PSCustomObject]@{
            Num       = $b.number
            Titulo    = $b.title
            Pendientes = $pending
            Items     = $total
            Url       = "https://github.com/users/$($b.ownerLogin)/projects/$($b.number)"
        }
    }

    # Boards with pending work first, most pending on top
    $rows = $rows | Sort-Object -Property @{Expression={ if ($_.Pendientes -is [int]) { -$_.Pendientes } else { 1 } }}

    foreach ($r in $rows) {
        $color = if ($r.Pendientes -is [int] -and $r.Pendientes -gt 0) { "Yellow" } else { "DarkGray" }
        Write-Host ("  #{0,-3} {1,-45} pendientes: {2,-4} items: {3}" -f $r.Num, $r.Titulo, $r.Pendientes, $r.Items) -ForegroundColor $color
        Write-Host ("        {0}" -f $r.Url) -ForegroundColor DarkCyan
    }
    Write-Host ""
    Write-Host "Siguiente paso: Board-Work.ps1 -ProjectNum <num> para ver los pendientes de un board." -ForegroundColor Cyan
    exit 0
}

if ($ProjectNum -le 0) {
    throw "Usa -ListBoards, o -ProjectNum <n> (opcionalmente con -Start <issueNum> o -Parallel <nums>)."
}

if ($Start -gt 0 -and $Parallel.Count -gt 0) {
    throw "-Start y -Parallel son mutuamente exclusivos: usa uno u otro."
}

$boardUrl = Get-BoardUrl $ProjectNum

# ==============================================================================
# MODE 2: -ProjectNum  -> pending items of one board
# ==============================================================================
if ($Start -le 0 -and $ToReview -le 0 -and $Parallel.Count -eq 0) {
    Write-Host "=== Pendientes del board #$ProjectNum de $Owner ===" -ForegroundColor Cyan
    Write-Host ""

    $items   = (gh project item-list $ProjectNum --owner $Owner --format json --limit 200 | ConvertFrom-Json).items
    $pending = @($items | Where-Object { Test-Pending $_ })

    if ($pending.Count -eq 0) {
        Write-Host "Sin pendientes. Todo el board esta en progreso o terminado." -ForegroundColor Green
        Write-Host ""
        Write-Host "Board: $boardUrl" -ForegroundColor Cyan
        exit 0
    }

    # Sort: priority name ascending (P0 < P1 < P2), empty priority last
    $pending = $pending | Sort-Object -Property @{Expression={ if ($_.priority) { $_.priority } else { "zz" } }}

    foreach ($p in $pending) {
        $prio = if ($p.priority) { $p.priority } else { "(sin prio)" }
        $size = if ($p.size)     { $p.size }     else { "-" }
        $type = if ($p.type)     { $p.type }     else { "-" }
        if ($p.content.type -eq "DraftIssue") {
            Write-Host ("  [draft]  {0}" -f $p.title) -ForegroundColor DarkYellow
            Write-Host  "           (nota draft - conviertela a issue real con /board fill antes de trabajarla)" -ForegroundColor DarkGray
        } elseif (@($p.labels) -contains "blocked") {
            Write-Host ("  #{0,-4} [BLOCKED] {1}" -f $p.content.number, $p.title) -ForegroundColor Red
            Write-Host  "        bloqueado por una dependencia - no se puede empezar (quita el label 'blocked' al desbloquearse)" -ForegroundColor DarkGray
        } else {
            $repo = $p.content.repository
            Write-Host ("  #{0,-4} {1}" -f $p.content.number, $p.title) -ForegroundColor Yellow
            Write-Host ("        {0} | Size {1} | {2} | {3}" -f $prio, $size, $type, $repo) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host ("Total: {0} pendiente(s)." -f $pending.Count) -ForegroundColor Yellow

    # Multi-session: show what other LIVE local sessions are working right now
    $sessions = @(Read-SessionRegistry)
    if ($sessions.Count -gt 0) {
        Write-Host ""
        Write-Host "Sesiones activas en esta maquina:" -ForegroundColor Cyan
        foreach ($s in $sessions) {
            Write-Host ("  #{0}  rama {1}  (PID {2} vivo, desde {3}) en {4}" -f $s.issue, $s.branch, $s.sessionPid, $s.started, $s.workPath) -ForegroundColor DarkCyan
        }
    }
    Write-Host ""
    Write-Host "Siguiente paso: Board-Work.ps1 -ProjectNum $ProjectNum -Start <issueNum> (o -Parallel <n1,n2,...>)." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

# ==============================================================================
# MODE 4: -ProjectNum -ToReview <issueNum>  -> move item to the "In Review" column
# The work flow calls this after opening the PR: the change is now in review /
# testing while the gate runs. Merge later moves it to Done (close->Done + fill).
# ==============================================================================
if ($ToReview -gt 0) {
    $projData = gh api graphql -f query='
query($owner:String!, $num:Int!) {
  user(login:$owner) {
    projectV2(number:$num) {
      id
      fields(first:30) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } } }
    }
  }
}' -F "owner=$Owner" -F "num=$ProjectNum" | ConvertFrom-Json

    $projectId  = $projData.data.user.projectV2.id
    if (-not $projectId) { throw "Board #$ProjectNum no encontrado para $Owner." }
    $statusNode = $projData.data.user.projectV2.fields.nodes | Where-Object { $_.name -eq "Status" }
    $reviewId   = ($statusNode.options | Where-Object { $_.name -eq "In Review" }).id
    if (-not $reviewId) {
        throw "El board #$ProjectNum no tiene la opcion 'In Review' en Status. Agregala (/board field) antes de usar -ToReview."
    }

    # Find the item (one retry for GitHub eventual consistency, like -Start).
    $item = $null
    foreach ($attempt in 1..2) {
        $itemsData = gh api graphql -f query='
query($proj:ID!) {
  node(id:$proj) {
    ... on ProjectV2 {
      items(first:100) { nodes { id content { __typename ... on Issue { number title } } } } }
  }
}' -F "proj=$projectId" | ConvertFrom-Json
        $item = $itemsData.data.node.items.nodes |
                Where-Object { $_.content.__typename -eq "Issue" -and $_.content.number -eq $ToReview } |
                Select-Object -First 1
        if ($item) { break }
        if ($attempt -eq 1) { Start-Sleep -Seconds 3 }
    }
    if (-not $item) { throw "Issue #$ToReview no esta en el board #$ProjectNum." }

    if ($DryRun) {
        Write-Host "DRY-RUN: #$ToReview '$($item.content.title)' -> Status In Review (no ejecutado)." -ForegroundColor Gray
        Write-Host "Board: $boardUrl" -ForegroundColor Cyan
        exit 0
    }

    gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -f "proj=$projectId" -f "item=$($item.id)" -f "field=$($statusNode.id)" -f "opt=$reviewId" | Out-Null
    Write-Host "OK  #$ToReview '$($item.content.title)' -> Status In Review (en review/testing)." -ForegroundColor Green
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

# ==============================================================================
# MODE 5: -ProjectNum -Parallel <issueNums>  -> batch-start, one worktree each
# ==============================================================================
if ($Parallel.Count -gt 0) {
    # De-dup while preserving the requested order.
    $queue = @()
    foreach ($n in $Parallel) { if ($n -gt 0 -and $queue -notcontains $n) { $queue += $n } }
    if ($queue.Count -eq 0) { throw "-Parallel no recibio numeros de issue validos." }

    Write-Host "=== Parallel batch-start (board #$ProjectNum de $Owner) ===" -ForegroundColor Cyan
    Write-Host ("  Issues: {0}" -f ($queue -join ', ')) -ForegroundColor DarkGray
    if ($DryRun) { Write-Host "  Modo DRY-RUN - planifica sin mutar el board ni tocar git." -ForegroundColor Gray }
    Write-Host ""

    $ctx = Resolve-BoardStatus $Owner $ProjectNum

    # Fresh base so each independent worktree branches off up-to-date main.
    $baseRef = ""
    if (-not $DryRun) {
        git fetch origin --quiet 2>$null
        git rev-parse --verify --quiet origin/main 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $baseRef = "origin/main" }
    }

    $results = @()
    foreach ($n in $queue) {
        Write-Host ("--- #{0} ---" -f $n) -ForegroundColor Cyan
        $r = Invoke-IssueStart -IssueNum $n -Ctx $ctx -Owner $Owner -MakeBranch -PreferWorktree `
                               -BaseRef $baseRef -DryRunStart:$DryRun `
                               -IgnoreBlocked:$IgnoreBlocked -TakeOver:$TakeOver
        $results += $r
        Write-Host ""
    }

    # -- Summary ---------------------------------------------------------------
    Write-Host "===== RESUMEN PARALELO =====" -ForegroundColor Cyan
    $started = @($results | Where-Object { $_.started })
    $planned = @($results | Where-Object { $_.dryRun -and -not $_.skipped })
    $skipped = @($results | Where-Object { $_.skipped })
    foreach ($r in $results) {
        if ($r.skipped) {
            Write-Host ("  #{0,-4} SKIP  {1}" -f $r.issue, $r.skipped) -ForegroundColor Red
        } elseif ($r.dryRun) {
            Write-Host ("  #{0,-4} plan  -> rama {1}" -f $r.issue, $r.branch) -ForegroundColor Gray
        } else {
            Write-Host ("  #{0,-4} OK    -> {1}" -f $r.issue, $r.workPath) -ForegroundColor Green
        }
    }
    Write-Host ""

    if ($DryRun) {
        Write-Host ("DRY-RUN: {0} se iniciarian, {1} se saltarian. Ningun cambio hecho." -f $planned.Count, $skipped.Count) -ForegroundColor Gray
    } else {
        Write-Host ("Iniciados: {0} / {1}. Worktrees listos, uno por issue." -f $started.Count, $queue.Count) -ForegroundColor Yellow
        if ($started.Count -gt 0 -and -not $Launch) {
            Write-Host ""
            Write-Host "Cada worktree tiene su rama y su claim. Trabaja cada issue en su carpeta:" -ForegroundColor Cyan
            foreach ($r in $started) {
                if ($r.workPath) { Write-Host ("  cd `"{0}`"   # #{1}" -f $r.workPath, $r.issue) -ForegroundColor DarkCyan }
            }
            Write-Host ""
            Write-Host "Al terminar cada uno: PR con 'Closes #<num>' + review gate (Board-ReviewGate.ps1)." -ForegroundColor DarkGray
            Write-Host "Agrega -Launch para abrir una sesion Claude por worktree automaticamente." -ForegroundColor DarkGray
        }
    }

    # -- Launch: one visible Claude session per worktree (-Launch) --------------
    if ($Launch) {
        Write-Host ""
        if ($DryRun) {
            Write-Host "----- LAUNCH (preview, -DryRun no lanza nada) -----" -ForegroundColor Cyan
            foreach ($r in $planned) {
                $repoName    = ($r.repo -split '/')[1]
                $previewPath = Join-Path (Split-Path (Get-Location) -Parent) "$repoName--issue-$($r.issue)"
                Start-WorktreeSession -IssueNum $r.issue -Repo $r.repo -Branch $r.branch -WorkPath $previewPath -Preview | Out-Null
            }
        } else {
            Write-Host "----- LANZANDO SESIONES CLAUDE -----" -ForegroundColor Cyan
            $launched = 0
            foreach ($r in $started) {
                if ($r.workPath) {
                    Start-WorktreeSession -IssueNum $r.issue -Repo $r.repo -Branch $r.branch -WorkPath $r.workPath | Out-Null
                    $launched++
                }
            }
            Write-Host ""
            Write-Host ("Lanzadas: {0} sesion(es). Cada una trabaja su issue hasta el PR + review gate." -f $launched) -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

# ==============================================================================
# MODE 3: -ProjectNum -Start <issueNum>  -> move to In Progress + assign + context
# ==============================================================================
Write-Host "=== Empezando issue #$Start (board #$ProjectNum de $Owner) ===" -ForegroundColor Cyan
Write-Host ""

$ctx = Resolve-BoardStatus $Owner $ProjectNum
$r = Invoke-IssueStart -IssueNum $Start -Ctx $ctx -Owner $Owner -MakeBranch:$Branch `
                       -DryRunStart:$DryRun -IgnoreBlocked:$IgnoreBlocked -TakeOver:$TakeOver

if ($r.skipped) {
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 1
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Modo DRY-RUN - ningun cambio ejecutado." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-IssueContext $Start $r.repo
Write-Host ""
Write-Host "Issue #$Start listo para trabajar (In Progress, asignado a $Owner)." -ForegroundColor Green
Write-Host "AL TERMINAR: New-BoardPR.ps1 -Issue $Start  (push + PR 'Closes #$Start' con la cuenta correcta) - NO commit directo a main." -ForegroundColor Yellow
Write-Host "(asi GitHub llena solo la columna 'Linked pull requests' del board)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Board: $boardUrl" -ForegroundColor Cyan
