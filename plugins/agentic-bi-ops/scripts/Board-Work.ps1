<#
.SYNOPSIS
    Show pending work across boards and start working an issue.

.DESCRIPTION
    Three modes, designed for the /board work flow:

      1. -ListBoards [-Repo <owner/name>]
         Lists boards with their pending count (items in Todo or no Status),
         so the user can pick which board to work from. Without -Repo it
         lists EVERY board of the owner (backups excluded); with -Repo it
         lists only the boards LINKED to that repository (repository.projectsV2),
         which is the "current repo" scope of the /board work flow.

      2. -ProjectNum <n>
         Lists the PENDING items of that board (Status = Todo or empty),
         sorted by Priority (P0 first, empty last), with issue number, title,
         Priority, Size and Type. Draft notes are flagged (convert them with
         /board fill before starting them).

      3. -ProjectNum <n> -Start <issueNum>
         Starts working that issue: moves the board item to "In Progress",
         assigns the owner, and prints the full issue context (labels,
         body, sub-issues) so the agent can begin working it in-session.
         Supports -DryRun to preview without mutating.

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

.PARAMETER DryRun
    With -Start: print what would change without executing.

.PARAMETER Branch
    With -Start: also create and checkout a work branch issue-<num>-<slug>
    (only when the current directory is a clone of the issue's repo).
    Finishing the work MUST then go through a PR with "Closes #<num>" so
    GitHub fills the Linked pull requests column on the board by itself.

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Defaults to GITHUB_TOKEN_PERSONAL;
    use GITHUB_TOKEN_BUSINESS for the PAL-Devs account.

.EXAMPLE
    .\Board-Work.ps1 -ListBoards
    .\Board-Work.ps1 -ListBoards -Repo CSalcedoDataBI/agentic-bi-ops
    .\Board-Work.ps1 -ProjectNum 13
    .\Board-Work.ps1 -ProjectNum 13 -Start 12 -DryRun
    .\Board-Work.ps1 -ProjectNum 13 -Start 12
#>
[CmdletBinding()]
param(
    [string]$Owner    = "CSalcedoDataBI",
    [switch]$ListBoards,
    [string]$Repo     = "",
    [int]   $ProjectNum = 0,
    [int]   $Start      = 0,
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

# An item is PENDING when its Status is Todo or it has no Status yet.
function Test-Pending($item) {
    (-not $item.status) -or ($item.status -eq "Todo")
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
    throw "Usa -ListBoards, o -ProjectNum <n> (opcionalmente con -Start <issueNum>)."
}

$boardUrl = Get-BoardUrl $ProjectNum

# ==============================================================================
# MODE 2: -ProjectNum  -> pending items of one board
# ==============================================================================
if ($Start -le 0) {
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
    Write-Host "Siguiente paso: Board-Work.ps1 -ProjectNum $ProjectNum -Start <issueNum> para empezar uno." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

# ==============================================================================
# MODE 3: -ProjectNum -Start <issueNum>  -> move to In Progress + assign + context
# ==============================================================================
Write-Host "=== Empezando issue #$Start (board #$ProjectNum de $Owner) ===" -ForegroundColor Cyan
Write-Host ""

# -- Resolve project + Status field via GraphQL (same pattern as Board-Fill) ---
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
}' -F "owner=$Owner" -F "num=$ProjectNum" | ConvertFrom-Json

$projectId  = $projData.data.user.projectV2.id
if (-not $projectId) { throw "Board #$ProjectNum no encontrado para $Owner." }
$statusNode = $projData.data.user.projectV2.fields.nodes | Where-Object { $_.name -eq "Status" }
$inProgId   = ($statusNode.options | Where-Object { $_.name -eq "In Progress" }).id
if (-not $inProgId) { throw "El board #$ProjectNum no tiene la opcion 'In Progress' en Status." }

# -- Find the board item for that issue number ---------------------------------
# One retry with a short wait: an item added seconds ago may not be visible yet
# in the items query (GitHub eventual consistency).
$item = $null
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
            Where-Object { $_.content.__typename -eq "Issue" -and $_.content.number -eq $Start } |
            Select-Object -First 1
    if ($item) { break }
    if ($attempt -eq 1) {
        Write-Host "  (issue #$Start aun no visible en el board - reintentando en 4s...)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 4
    }
}
if (-not $item) { throw "Issue #$Start no esta en el board #$ProjectNum. Agregalo primero con /board add." }

$repo          = $item.content.repository.nameWithOwner
$currentStatus = ($item.fieldValues.nodes | Where-Object { $_.field.name -eq "Status" }).name
if (-not $currentStatus) { $currentStatus = "(vacio)" }

if ($item.content.state -eq "CLOSED") {
    Write-Host "AVISO: el issue #$Start esta CERRADO. Reabrelo antes de trabajarlo (gh issue reopen $Start --repo $repo)." -ForegroundColor Red
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 1
}

# -- Dependency check (Issues BP): refuse to start a blocked issue --------------
if (-not $IgnoreBlocked) {
    $blockers = @()
    $issueLabels = @((gh issue view $Start --repo $repo --json labels | ConvertFrom-Json).labels.name)
    if ($issueLabels -contains "blocked") { $blockers += "label 'blocked' presente" }
    # Native blocked-by dependencies (best-effort: API may not exist for the account)
    try {
        $deps = gh api "repos/$repo/issues/$Start/dependencies/blocked_by" 2>$null | ConvertFrom-Json
        foreach ($d in @($deps | Where-Object { $_.state -eq "open" })) {
            $blockers += "bloqueado por #$($d.number) '$($d.title)' (abierto)"
        }
    } catch { }
    if ($blockers.Count -gt 0) {
        Write-Host "BLOQUEADO - no se empieza #${Start}:" -ForegroundColor Red
        $blockers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "Resuelve la dependencia (o usa -IgnoreBlocked si es un falso positivo)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Board: $boardUrl" -ForegroundColor Cyan
        exit 1
    }
}

# -- Issue lock (multi-session): refuse an issue another session already has ----
$assignees = @($item.content.assignees.nodes.login)
if (-not $TakeOver -and $currentStatus -eq "In Progress" -and $assignees.Count -gt 0) {
    Write-Host "OCUPADO - el issue #$Start ya esta In Progress (asignado: $($assignees -join ', '))." -ForegroundColor Red
    # Show the last claim fingerprint if one exists
    $lastClaim = gh api "repos/$repo/issues/$Start/comments" --jq '[.[] | select(.body | startswith("[abios-claim]"))] | last | .body' 2>$null
    if ($lastClaim -and $lastClaim -ne "null") {
        Write-Host "  Ultimo claim: $lastClaim" -ForegroundColor Yellow
    }
    Write-Host "Probablemente otra sesion de Claude lo esta trabajando. Si NO es asi (sesion muerta" -ForegroundColor Yellow
    Write-Host "o quieres retomarlo a proposito), re-ejecuta con -TakeOver." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 1
}

Write-Host ("  #{0} {1}" -f $Start, $item.content.title) -ForegroundColor Yellow
Write-Host ("  Repo: {0} | Status actual: {1}" -f $repo, $currentStatus) -ForegroundColor DarkGray
Write-Host ""
# Work branch name: issue-<num>-<slug-from-title>
$slug = ($item.content.title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
if ($slug.Length -gt 40) {
    $slug = $slug.Substring(0, 40)
    if ($slug.Contains('-')) { $slug = $slug.Substring(0, $slug.LastIndexOf('-')) }  # no cortar palabras
    $slug = $slug.Trim('-')
}
$branchName = "issue-$Start-$slug"

Write-Host "  Plan:" -ForegroundColor Cyan
Write-Host "    -> Status [$currentStatus] -> In Progress"
Write-Host "    -> Assignee -> $Owner"
if ($Branch) { Write-Host "    -> Rama de trabajo: $branchName" }
Write-Host ""

if ($DryRun) {
    Write-Host "Modo DRY-RUN - ningun cambio ejecutado." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Board: $boardUrl" -ForegroundColor Cyan
    exit 0
}

# -- Execute: Status -> In Progress ---------------------------------------------
gh api graphql -f query='
mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$proj, itemId:$item, fieldId:$field,
    value:{singleSelectOptionId:$opt}
  }) { projectV2Item { id } }
}' -f "proj=$projectId" -f "item=$($item.id)" -f "field=$($statusNode.id)" -f "opt=$inProgId" | Out-Null
Write-Host "  OK  Status -> In Progress" -ForegroundColor Green

# -- Execute: assign owner ------------------------------------------------------
try {
    gh api "repos/$repo/issues/$Start/assignees" -X POST -F "assignees[]=$Owner" | Out-Null
    Write-Host "  OK  Assignee -> $Owner" -ForegroundColor Green
} catch {
    Write-Host "  WARN no se pudo asignar: $_" -ForegroundColor DarkYellow
}

# -- Execute: claim fingerprint (multi-session diagnostics) ---------------------
$claimNote = if ($TakeOver) { "TAKEOVER" } else { "claim" }
$fingerprint = "[abios-claim] $claimNote por sesion Claude en $env:COMPUTERNAME (PID $PID) - $(Get-Date -Format 'yyyy-MM-dd HH:mm') - rama $branchName"
try {
    gh issue comment $Start --repo $repo --body $fingerprint | Out-Null
    Write-Host "  OK  Claim registrado ($claimNote)" -ForegroundColor Green
} catch {
    Write-Host "  WARN no se pudo registrar el claim: $_" -ForegroundColor DarkYellow
}

# -- Execute: work branch (only if cwd is a clone of the issue's repo) ----------
if ($Branch) {
    $originUrl = ""
    try { $originUrl = (git remote get-url origin 2>$null) } catch { }
    if ($originUrl -notmatch [regex]::Escape($repo)) {
        Write-Host "  WARN el directorio actual no es un clon de $repo - rama NO creada." -ForegroundColor DarkYellow
        Write-Host "       Crea la rama en ese repo con: git checkout -b $branchName" -ForegroundColor DarkYellow
    } else {
        # Dirty-tree guard (multi-session): NEVER switch branches under another session's feet.
        $dirty     = @(git status --porcelain 2>$null)
        $curBranch = git branch --show-current 2>$null
        if ($dirty.Count -gt 0 -and $curBranch -ne $branchName) {
            Write-Host "  OCUPADO: el working tree tiene $($dirty.Count) cambio(s) sin commitear (rama actual: $curBranch)." -ForegroundColor Red
            Write-Host "       Otra sesion puede estar trabajando en esta carpeta - NO cambio de rama." -ForegroundColor Yellow
            Write-Host "       Opciones: commitea/stashea esos cambios, o trabaja #$Start en un worktree:" -ForegroundColor Yellow
            Write-Host "         git worktree add ../$(($repo -split '/')[1])--issue-$Start -b $branchName" -ForegroundColor Yellow
        } elseif ($curBranch -and $curBranch -match '^issue-\d+' -and $curBranch -ne $branchName) {
            Write-Host "  OCUPADO: esta carpeta esta en la rama '$curBranch' (otro issue en curso)." -ForegroundColor Red
            Write-Host "       Otra sesion parece activa aqui - NO cambio de rama." -ForegroundColor Yellow
            Write-Host "       Trabaja #$Start en un worktree:" -ForegroundColor Yellow
            Write-Host "         git worktree add ../$(($repo -split '/')[1])--issue-$Start -b $branchName" -ForegroundColor Yellow
        } else {
            git rev-parse --verify --quiet $branchName 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                git checkout $branchName 2>&1 | Out-Null
                Write-Host "  OK  Rama $branchName ya existia - checkout hecho" -ForegroundColor Green
            } else {
                git checkout -b $branchName 2>&1 | Out-Null
                Write-Host "  OK  Rama $branchName creada y activa" -ForegroundColor Green
            }
        }
    }
}
Write-Host ""

# -- Print full issue context so the agent can start working --------------------
$issue = gh issue view $Start --repo $repo --json title,body,labels,milestone,url,state | ConvertFrom-Json

Write-Host "----- CONTEXTO DEL ISSUE -----" -ForegroundColor Cyan
Write-Host ("Titulo : {0}" -f $issue.title)
Write-Host ("URL    : {0}" -f $issue.url)
$labelNames = @($issue.labels | ForEach-Object { $_.name })
if ($labelNames.Count -gt 0) { Write-Host ("Labels : {0}" -f ($labelNames -join ", ")) }
if ($issue.milestone)        { Write-Host ("Hito   : {0}" -f $issue.milestone.title) }
Write-Host ""
if ($issue.body) { Write-Host $issue.body } else { Write-Host "(sin descripcion)" -ForegroundColor DarkGray }
Write-Host ""

# Sub-issues (optional API - ignore failures silently)
try {
    $repoParts = $repo -split "/"
    $subData = gh api graphql -f query='
query($o:String!, $r:String!, $n:Int!) {
  repository(owner:$o, name:$r) {
    issue(number:$n) {
      subIssues(first:30) { nodes { number title state } }
    }
  }
}' -F "o=$($repoParts[0])" -F "r=$($repoParts[1])" -F "n=$Start" 2>$null | ConvertFrom-Json
    $subs = @($subData.data.repository.issue.subIssues.nodes)
    if ($subs.Count -gt 0) {
        Write-Host "Sub-issues:" -ForegroundColor Cyan
        foreach ($s in $subs) { Write-Host ("  #{0} [{1}] {2}" -f $s.number, $s.state, $s.title) }
        Write-Host ""
    }
} catch { }

Write-Host "------------------------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "Issue #$Start listo para trabajar (In Progress, asignado a $Owner)." -ForegroundColor Green
Write-Host "AL TERMINAR: push de la rama y PR con 'Closes #$Start' en el cuerpo - NO commit directo a main." -ForegroundColor Yellow
Write-Host "(asi GitHub llena solo la columna 'Linked pull requests' del board)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Board: $boardUrl" -ForegroundColor Cyan
