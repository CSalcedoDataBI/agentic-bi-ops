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

.PARAMETER Sessions
    Monitor mode: list the LIVE parallel-session fleet from
    .agentic-bi-ops/sessions.json (branch, worktree, launch method, and the
    PR opened for each branch). Dead-PID entries are pruned on read. Needs no
    -ProjectNum.

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
    .\Board-Work.ps1 -Sessions
    .\Board-Work.ps1 -ProjectNum 13 -ToReview 12
#>
[CmdletBinding()]
param(
    [string]$Owner    = "CSalcedoDataBI",
    [switch]$ListBoards,
    [string]$Repo     = "",
    [int]   $ProjectNum = 0,
    [int]   $Start      = 0,
    # Accept as strings, not [int[]]: when the script is invoked via `pwsh -File`,
    # `-Parallel 129,130` arrives as the single string "129,130" (comma read as a
    # thousands separator -> 129130), NOT a 2-element array. Get-ParallelQueue
    # splits each token on ',' so both `-File` and native-array calls work.
    [string[]] $Parallel = @(),
    [switch]$Launch,
    [switch]$Sessions,
    [int]   $ToReview   = 0,
    [switch]$DryRun,
    [switch]$Branch,
    [switch]$IgnoreBlocked,
    [switch]$TakeOver,
    [string]$TokenVar      = "GITHUB_TOKEN_PERSONAL",
    # Only a plain env-var identifier - it gets interpolated into the spawned
    # -Command string, so reject anything that could inject (';', quotes, spaces).
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
    [string]$ClaudeAuthVar = "ANTHROPIC_API_KEY"
)

$ErrorActionPreference = "Stop"

# NOTE: the GH_TOKEN check lives in the main-entry guard below (after every function
# is defined) so the pure helpers can be dot-sourced for unit tests without a token
# and without side effects (set $env:ABIOS_BOARDWORK_DOTSOURCE=1 before dot-sourcing).

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

function Write-SessionRegistryEntry {
    param(
        [int]$IssueNum, [string]$Branch, [string]$WorkPath, [string]$Repo = "",
        [int]$SessionPid = 0, [string]$Via = ""
    )
    $p = Get-SessionRegistryPath
    if (-not $p) { return }
    # PID identity: an explicit spawned-session PID wins (a parallel launch tracks the
    # actual worktree session, not the launcher); otherwise the PARENT of this script
    # (the long-lived host session, since the script's own PID dies on return).
    $trackPid = $SessionPid
    if ($trackPid -le 0) {
        try { $trackPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId } catch { }
    }
    if (-not $trackPid) { return }
    # Preserve fields already recorded for this issue (e.g. repo set at start time)
    # when a later launch updates only the PID/via.
    $prev = @(Read-SessionRegistry | Where-Object { $_.issue -eq $IssueNum }) | Select-Object -First 1
    if (-not $Repo -and $prev) { $Repo = $prev.repo }
    if (-not $Branch -and $prev) { $Branch = $prev.branch }
    if (-not $WorkPath -and $prev) { $WorkPath = $prev.workPath }
    if (-not $Via -and $prev) { $Via = $prev.via }
    $entries = @(Read-SessionRegistry | Where-Object { $_.issue -ne $IssueNum })
    $entries += [PSCustomObject]@{
        issue      = $IssueNum
        repo       = $Repo
        branch     = $Branch
        workPath   = $WorkPath
        sessionPid = $trackPid
        via        = $Via
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

# Normalize a -Parallel request into the batch queue: split comma-separated tokens
# (so `pwsh -File ... -Parallel 129,130` -> "129,130" splits into 129 and 130),
# drop non-positive/non-numeric values, and de-duplicate while preserving the
# requested order. Pure -> unit-testable.
function Get-ParallelQueue([string[]]$nums) {
    $queue = @()
    foreach ($tok in $nums) {
        if ($null -eq $tok) { continue }
        foreach ($part in ($tok -split ',')) {
            $part = $part.Trim()
            if ($part -eq '') { continue }
            $n = 0
            if (-not [int]::TryParse($part, [ref]$n)) { continue }
            if ($n -gt 0 -and $queue -notcontains $n) { $queue += $n }
        }
    }
    # No unary-comma wrap: it would turn an empty queue into a 1-element array
    # (an array holding @()). Callers wrap with @() to normalize the single case.
    return $queue
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

# Last [abios-claim] fingerprint comment on an issue (or empty). Wrapped so the
# multi-session lock path can be unit-tested without a live gh call.
function Get-LastClaim([string]$repo, [int]$issueNum) {
    return (gh api "repos/$repo/issues/$issueNum/comments" --jq '[.[] | select(.body | startswith("[abios-claim]"))] | last | .body' 2>$null)
}

# Where an issue's worktree lives: <parent>/<repo>--worktrees/issue-<n>. Pure ->
# unit-testable. All worktrees are GROUPED under one `<repo>--worktrees` folder
# (instead of scattered siblings `<repo>--issue-<n>`), which keeps the repo's parent
# directory clean, makes `git worktree list` read grouped, and lets you clean the
# whole fleet by removing a single folder.
function Get-IssueWorktreePath([string]$repo, [int]$issueNum, [string]$parentDir) {
    $repoName = ($repo -split '/')[1]
    return (Join-Path (Join-Path $parentDir "$repoName--worktrees") "issue-$issueNum")
}

# Create an isolated worktree <parent>/<repo>--worktrees/issue-<n> for a branch.
# Returns the path or $null. $baseRef (e.g. origin/main) is used only when creating a
# NEW branch: parallel starts each independent issue off a fresh main; single start
# passes "" to keep branching off the current HEAD.
function New-IssueWorktree([string]$repo, [int]$issueNum, [string]$branchName, [string]$baseRef = "") {
    $wtPath   = Get-IssueWorktreePath $repo $issueNum (Split-Path (Get-Location) -Parent)
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
    # Ensure the grouping folder (<repo>--worktrees) exists before adding into it.
    # `git worktree add` creates leading dirs, but this keeps the intent explicit.
    $wtParent = Split-Path $wtPath -Parent
    if (-not (Test-Path $wtParent)) { New-Item -ItemType Directory -Path $wtParent -Force | Out-Null }
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
        $lastClaim = Get-LastClaim $repo $IssueNum
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
            Write-SessionRegistryEntry -IssueNum $IssueNum -Branch $branchName -WorkPath $result.workPath -Repo $repo
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
    return ("You are running AUTONOMOUSLY - permissions are pre-approved, so work this " +
            "task end-to-end WITHOUT stopping to ask for confirmation. " +
            "Pick up GitHub issue #$issueNum in $repo. It is already In Progress and claimed, " +
            "on branch $branch in this worktree ($workPath). Steps: " +
            "(1) read it with: gh issue view $issueNum --repo $repo ; " +
            "(2) implement it fully in this worktree and commit your changes ; " +
            "(3) open the PR with: pwsh plugins/agentic-bi-ops/scripts/New-BoardPR.ps1 -Issue $issueNum " +
            "and note the PR number it prints ; " +
            "(4) pass the review gate: pwsh plugins/agentic-bi-ops/scripts/Board-ReviewGate.ps1 -PR <pr> ; " +
            "address any feedback and re-run until it is green ; " +
            "(5) merge it (ruleset-safe): pwsh plugins/agentic-bi-ops/scripts/Board-Merge.ps1 -PR <pr> . " +
            "Work ONLY this issue - never touch other worktrees or issues. When the PR is merged, you are done.")
}

# Build the exact launch command for a worktree session. Returns an object
# { launcher, args, briefingFile, launchScriptFile, launchScript } WITHOUT spawning -
# pure enough to unit-test and to preview under -DryRun. Windows Terminal tab when
# 'wt' exists (grouped in a named window), else a standalone pwsh window.
#
# CRITICAL - why the setup runs from a .ps1 FILE, not an inline `-Command`:
# Windows Terminal's `wt` command line uses ';' as its OWN sub-command separator
# (new-tab ; split-pane ; ...). A `pwsh -Command "a; b; c"` passed to `wt` therefore
# had its ';' eaten by wt, which split ONE intended tab into FOUR (one per segment) -
# 2 issues -> 8 stray tabs, and the real `claude -p` landed in a bare tab with no
# auth setup, so no session actually worked its issue. Writing the setup+run to
# launch-<issue>.ps1 and launching `pwsh -NoExit -File <script>` puts ZERO ';' on
# wt's command line, so wt opens exactly one tab. The briefing is likewise passed by
# file so no long/quoted text ever hits the command line.
function Build-WorktreeLaunch([int]$issueNum, [string]$workPath, [string]$briefingFile, [string]$windowName = "abios-parallel", [string]$claudeAuthVar = "ANTHROPIC_API_KEY") {
    $tabTitle  = "issue-$issueNum"
    # Defense-in-depth: this name is interpolated into the spawned launch script,
    # so it MUST be a bare env-var identifier - never let ';'/quotes/spaces through.
    if ($claudeAuthVar -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "ClaudeAuthVar '$claudeAuthVar' is not a valid environment variable name."
    }
    # The spawned session is UNATTENDED, so it must never block on an interactive
    # prompt. Headless -p is the only mode that clears ALL of them: it skips the
    # new-worktree trust dialog AND the one-time "Bypass Permissions mode" accept
    # (both are interactive-only). --permission-mode bypassPermissions then keeps it
    # from pausing on per-tool approvals, --no-session-persistence stops parallel
    # sessions colliding on session state, and --verbose streams progress into the
    # tab so it visibly works instead of looking frozen. (An interactive
    # --dangerously-skip-permissions launch still stops at the one-time bypass
    # accept, which is why the tabs opened but never finished.)
    #
    # AUTH: a `claude` child gets no usable OAuth when spawned under the Claude
    # Desktop host (the host holds/refreshes the token in memory and strips the env),
    # so each tab authenticates with an explicit credential read at RUNTIME from the
    # Windows USER env var named by $claudeAuthVar (default ANTHROPIC_API_KEY; set it
    # to CLAUDE_CODE_OAUTH_TOKEN to bill the subscription instead). Only the var NAME
    # touches the command line - the secret never does. Re-reading from the registry
    # also RESTORES the value even when the launching context (Desktop) has stripped
    # it. We FIRST clear every competing Anthropic credential so the chosen one is
    # authoritative regardless of auth precedence - ANTHROPIC_API_KEY outranks
    # CLAUDE_CODE_OAUTH_TOKEN, so an inherited API key would otherwise silently
    # override a subscription token (or 401 if stale). We also drop the inherited
    # CLAUDE_CODE_* session markers so the child starts as a clean top-level session.
    # Double any single quote so a briefing path containing ' (valid on Windows, e.g. an
    # O'Brien user folder) can't break out of the single-quoted literal it is embedded in
    # inside the generated launch script (the Get-Content -LiteralPath '...' arg below).
    $safeBrief  = $briefingFile -replace "'", "''"
    # Each step on its OWN line (a .ps1 file), so no ';' is ever needed - which is the
    # whole point: ';' on wt's command line would split the tab (see the header note).
    $clearAuth  = 'Remove-Item Env:ANTHROPIC_API_KEY,Env:ANTHROPIC_AUTH_TOKEN,Env:CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue'
    $setAuth    = '$env:{0}=[Environment]::GetEnvironmentVariable(''{0}'',''User'')' -f $claudeAuthVar
    $clean      = 'Remove-Item Env:CLAUDECODE,Env:CLAUDE_CODE_SESSION_ID,Env:CLAUDE_CODE_CHILD_SESSION,Env:CLAUDE_CODE_ENTRYPOINT -ErrorAction SilentlyContinue'
    $run        = 'claude -p (Get-Content -Raw -LiteralPath ''{0}'') --permission-mode bypassPermissions --no-session-persistence --verbose' -f $safeBrief
    $launchScript = ($clearAuth, $setAuth, $clean, $run) -join "`r`n"
    # The launch script lives next to the briefing (same dir the caller chose).
    $launchScriptFile = Join-Path (Split-Path -Parent $briefingFile) "launch-$issueNum.ps1"
    $safeScriptPath   = $launchScriptFile   # a plain path arg (its own arg element -> Start-Process quotes it)
    if (Get-Command wt -ErrorAction SilentlyContinue) {
        return [PSCustomObject]@{
            launcher         = "wt"
            args             = @('-w', $windowName, 'new-tab', '--title', $tabTitle,
                                 '--startingDirectory', $workPath, 'pwsh', '-NoExit', '-File', $safeScriptPath)
            briefingFile     = $briefingFile
            launchScriptFile = $launchScriptFile
            launchScript     = $launchScript
            usesWt           = $true
        }
    }
    return [PSCustomObject]@{
        launcher         = "pwsh"
        args             = @('-NoExit', '-File', $safeScriptPath)
        briefingFile     = $briefingFile
        launchScriptFile = $launchScriptFile
        launchScript     = $launchScript
        usesWt           = $false
    }
}

# Pick which Windows USER env var each spawned session authenticates with. Pure ->
# testable. An EXPLICIT -ClaudeAuthVar always wins; otherwise prefer the subscription
# OAuth token (CLAUDE_CODE_OAUTH_TOKEN, billed to the plan) when it is present, else
# fall back to the given default (ANTHROPIC_API_KEY, per-token console billing).
function Resolve-ClaudeAuthVar([bool]$explicit, [string]$chosen, [bool]$oauthTokenPresent) {
    if ($explicit) { return $chosen }
    if ($oauthTokenPresent) { return 'CLAUDE_CODE_OAUTH_TOKEN' }
    return $chosen
}

# Spawn (or -Preview) ONE visible Claude session for a started worktree.
function Start-WorktreeSession {
    param(
        [int]$IssueNum, [string]$Repo, [string]$Branch, [string]$WorkPath,
        [string]$ClaudeAuthVar = "ANTHROPIC_API_KEY",
        [switch]$Preview
    )
    $abios = Get-AbiosDir
    $briefingFile = if ($abios) { Join-Path $abios "briefing-$IssueNum.txt" } else { Join-Path $WorkPath "briefing-$IssueNum.txt" }
    $plan  = Build-WorktreeLaunch $IssueNum $WorkPath $briefingFile "abios-parallel" $ClaudeAuthVar

    if ($Preview) {
        Write-Host ("  [preview] #{0}: {1} {2}" -f $IssueNum, $plan.launcher, ($plan.args -join ' ')) -ForegroundColor Gray
        Write-Host ("  [preview] #{0} launch script ({1}):" -f $IssueNum, $plan.launchScriptFile) -ForegroundColor DarkGray
        foreach ($ln in ($plan.launchScript -split "`r?`n")) { Write-Host ("             $ln") -ForegroundColor DarkGray }
        return $plan
    }

    if (-not $WorkPath -or -not (Test-Path $WorkPath)) {
        Write-Host "  WARN #${IssueNum}: worktree '$WorkPath' no existe - no se lanza sesion." -ForegroundColor DarkYellow
        return $null
    }
    # Persist the briefing so the spawned session reads it without command-line quoting.
    Set-Content -LiteralPath $briefingFile -Value (Get-SessionBriefing $IssueNum $Repo $Branch $WorkPath) -Encoding UTF8
    # Persist the launch script so wt/pwsh runs it via -File (no ';' on wt's command
    # line -> no stray tab-splitting). See Build-WorktreeLaunch header for the why.
    Set-Content -LiteralPath $plan.launchScriptFile -Value $plan.launchScript -Encoding UTF8
    $proc = $null
    try {
        if ($plan.usesWt) { $proc = Start-Process $plan.launcher -ArgumentList $plan.args -PassThru }
        else              { $proc = Start-Process $plan.launcher -ArgumentList $plan.args -WorkingDirectory $WorkPath -PassThru }
        $how = if ($plan.usesWt) { "WT tab 'issue-$IssueNum'" } else { "ventana pwsh" }
        Write-Host ("  OK  #{0}: sesion Claude lanzada ({1}) en {2}" -f $IssueNum, $how, $WorkPath) -ForegroundColor Green
    } catch {
        Write-Host "  FAIL #${IssueNum}: no se pudo lanzar la sesion: $_" -ForegroundColor Red
    }
    # Attach the spawned process so the caller can track its real PID in the registry.
    # NOTE: a 'wt' process forks the terminal host and exits fast, so its PID is not a
    # reliable liveness signal - only the standalone pwsh window's PID is tracked.
    $plan | Add-Member -NotePropertyName process -NotePropertyValue $proc -Force
    return $plan
}

# Monitor the local parallel-session fleet: list every LIVE registered session
# (Read-SessionRegistry prunes dead-PID entries on the way in) with its branch,
# worktree, launch method and - best-effort - the PR opened for its branch.
function Show-SessionFleet {
    $sessions = @(Read-SessionRegistry)
    Write-Host "=== Flota de sesiones activas (esta maquina) ===" -ForegroundColor Cyan
    Write-Host ""
    if ($sessions.Count -eq 0) {
        Write-Host "No hay sesiones vivas registradas en .agentic-bi-ops/sessions.json." -ForegroundColor DarkGray
        return
    }
    foreach ($s in ($sessions | Sort-Object issue)) {
        $via = if ($s.via) { $s.via } else { "-" }
        Write-Host ("  #{0,-4} {1}" -f $s.issue, $s.branch) -ForegroundColor Yellow
        Write-Host ("        PID {0} via {1} | host {2} | desde {3}" -f $s.sessionPid, $via, $s.host, $s.started) -ForegroundColor DarkGray
        if ($s.workPath) { Write-Host ("        {0}" -f $s.workPath) -ForegroundColor DarkGray }
        if ($s.repo -and $s.branch) {
            try {
                $pr = @(gh pr list --repo $s.repo --head $s.branch --state all --json number,state,url --limit 1 2>$null | ConvertFrom-Json)
                if ($pr.Count -gt 0) {
                    Write-Host ("        PR #{0} [{1}] {2}" -f $pr[0].number, $pr[0].state, $pr[0].url) -ForegroundColor DarkCyan
                }
            } catch { }
        }
    }
    Write-Host ""
    Write-Host ("Total: {0} sesion(es) viva(s). Las de PID muerto se podaron automaticamente." -f $sessions.Count) -ForegroundColor Cyan
}

# ==============================================================================
# Main entry. Dot-source guard: when the test harness sets ABIOS_BOARDWORK_DOTSOURCE,
# the script returns here with only the functions defined - no token check, no gh
# calls, no side effects - so the pure helpers can be unit-tested in isolation.
# ==============================================================================
if ($env:ABIOS_BOARDWORK_DOTSOURCE) { return }

# -- Token (respect GH_TOKEN if gh-account already set it) ---------------------
if (-not $env:GH_TOKEN) {
    $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User")
}
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

# ==============================================================================
# MODE 0: -Sessions  -> monitor the local parallel-session fleet
# ==============================================================================
if ($Sessions) {
    Show-SessionFleet
    exit 0
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
    # Normalize to the batch queue (drop <=0, de-dup, keep order).
    $queue = @(Get-ParallelQueue $Parallel)
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
        # Auto-prefer the subscription OAuth token when the caller did not pick an
        # auth var explicitly (see Resolve-ClaudeAuthVar).
        $oauthPresent  = [bool][System.Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', 'User')
        $ClaudeAuthVar = Resolve-ClaudeAuthVar $PSBoundParameters.ContainsKey('ClaudeAuthVar') $ClaudeAuthVar $oauthPresent
        if ($ClaudeAuthVar -eq 'CLAUDE_CODE_OAUTH_TOKEN') {
            Write-Host "  Auth: usando CLAUDE_CODE_OAUTH_TOKEN (suscripcion)." -ForegroundColor DarkGray
        }
        if ($DryRun) {
            Write-Host "----- LAUNCH (preview, -DryRun no lanza nada) -----" -ForegroundColor Cyan
            foreach ($r in $planned) {
                $repoName    = ($r.repo -split '/')[1]
                $previewPath = Join-Path (Split-Path (Get-Location) -Parent) "$repoName--issue-$($r.issue)"
                Start-WorktreeSession -IssueNum $r.issue -Repo $r.repo -Branch $r.branch -WorkPath $previewPath -ClaudeAuthVar $ClaudeAuthVar -Preview | Out-Null
            }
        } else {
            Write-Host "----- LANZANDO SESIONES CLAUDE -----" -ForegroundColor Cyan
            # Preflight: unattended headless sessions need an explicit credential in
            # the Windows USER env (the Desktop host's OAuth is not shared with child
            # processes). Without it every tab would 401 silently - warn and don't spawn.
            $claudeAuth = [System.Environment]::GetEnvironmentVariable($ClaudeAuthVar, "User")
            if (-not $claudeAuth) {
                Write-Host ""
                Write-Host ("  AUTH REQUERIDA - las sesiones headless necesitan '{0}' en tus variables de usuario." -f $ClaudeAuthVar) -ForegroundColor Red
                Write-Host "  (El login del Desktop NO se comparte con procesos hijos, darian 401.)" -ForegroundColor DarkYellow
                Write-Host "  Opcion A (API key, facturacion por consumo a tu cuenta de consola):" -ForegroundColor Yellow
                Write-Host "    setx ANTHROPIC_API_KEY <tu-api-key>" -ForegroundColor Gray
                Write-Host "  Opcion B (suscripcion Claude): genera un token y apunta el launcher a el:" -ForegroundColor Yellow
                Write-Host "    claude setup-token   ; setx CLAUDE_CODE_OAUTH_TOKEN <token>   ; luego -ClaudeAuthVar CLAUDE_CODE_OAUTH_TOKEN" -ForegroundColor Gray
                Write-Host "  Reinicia la terminal y re-lanza con -Launch (los worktrees ya estan listos; monitorea con -Sessions)." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Board: $boardUrl" -ForegroundColor Cyan
                exit 0
            }
            $launched = 0
            foreach ($r in $started) {
                if ($r.workPath) {
                    $spawn = Start-WorktreeSession -IssueNum $r.issue -Repo $r.repo -Branch $r.branch -WorkPath $r.workPath -ClaudeAuthVar $ClaudeAuthVar
                    $launched++
                    # Track the spawned session's own PID (pwsh window is reliable; a wt
                    # launcher forks and exits, so keep the host PID there).
                    $via = if ($spawn.usesWt) { "wt" } else { "pwsh" }
                    if ($spawn.process -and -not $spawn.usesWt) {
                        Write-SessionRegistryEntry -IssueNum $r.issue -SessionPid $spawn.process.Id -Via $via
                    } else {
                        Write-SessionRegistryEntry -IssueNum $r.issue -Via $via
                    }
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
