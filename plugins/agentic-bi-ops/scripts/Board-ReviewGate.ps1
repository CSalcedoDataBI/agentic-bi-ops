<#
.SYNOPSIS
    Review gate for /board work step 5: no PR merges blind.

.DESCRIPTION
    GitHub flow says merge only AFTER review/approval. This script is the
    deterministic gate the work flow runs between "PR opened" and "merge":

      1. Requests a GitHub Copilot code review (best-effort: if the account
         has no Copilot code review, it warns and continues - the agent must
         then do an explicit self-review of `gh pr diff`).
      2. If the PR touches any *.tmdl (a PBIP semantic model), runs the TMDL
         diff review (Tmdl-DiffReview.ps1) and prints a breaking-change report.
         Warn-only: it never changes the gate verdict (M3.3 adds hard blocking).
      3. Waits for CI checks on the PR (gh pr checks --watch). "No checks
         configured" counts as pass, with a note.
      4. Waits (up to -TimeoutMinutes) for the requested review to arrive,
         then reports: review decision, every review with author/state/body,
         and unresolved review-thread count.
      5. Verdict via exit code:
           0 -> gate PASSED (checks ok, no CHANGES_REQUESTED, no unresolved threads)
           1 -> gate BLOCKED (address the printed feedback, push, re-run)

    -InstallRuleset (once per repo, optional): installs a repository ruleset
    that requires a PR before merging into the default branch. Repo admins
    keep a bypass so tooling still works - the ruleset protects against
    accidental direct pushes; the gate itself is enforced by the work flow.

.PARAMETER Repo
    owner/name of the repository. Mandatory.

.PARAMETER PR
    Pull request number to gate. Mandatory unless -InstallRuleset.

.PARAMETER InstallRuleset
    Install the require-PR ruleset on the repo's default branch (idempotent).

.PARAMETER TimeoutMinutes
    Max minutes to wait for the requested review. Default 6.

.PARAMETER MaxLines
    Small-PR guard: warn when additions+deletions exceed this. Default 600.

.PARAMETER MaxFiles
    Small-PR guard: warn when changed files exceed this. Default 20.

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Defaults to GITHUB_TOKEN_PERSONAL.

.EXAMPLE
    .\Board-ReviewGate.ps1 -Repo CSalcedoDataBI/agentic-bi-ops -PR 50
    .\Board-ReviewGate.ps1 -Repo CSalcedoDataBI/agentic-bi-ops -InstallRuleset
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [int]   $PR = 0,
    [switch]$InstallRuleset,
    [int]   $TimeoutMinutes = 6,
    [int]   $MaxLines = 600,
    [int]   $MaxFiles = 20,
    [string]$TokenVar = "GITHUB_TOKEN_PERSONAL"
)

$ErrorActionPreference = "Stop"

if (-not $env:GH_TOKEN) {
    $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User")
}
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

$rp = $Repo -split "/"

# ==============================================================================
# -InstallRuleset: require a PR before merging into the default branch
# ==============================================================================
if ($InstallRuleset) {
    $name = "pr-before-merge (agentic-bi-ops)"
    $existing = gh api "repos/$Repo/rulesets" 2>$null | ConvertFrom-Json
    if (@($existing | Where-Object { $_.name -eq $name }).Count -gt 0) {
        Write-Host "Ruleset '$name' ya existe en $Repo - nada que hacer." -ForegroundColor Green
        exit 0
    }
    $payload = @{
        name        = $name
        target      = "branch"
        enforcement = "active"
        conditions  = @{ ref_name = @{ include = @("~DEFAULT_BRANCH"); exclude = @() } }
        rules       = @(@{
            type       = "pull_request"
            parameters = @{
                required_approving_review_count   = 0
                dismiss_stale_reviews_on_push     = $false
                require_code_owner_review         = $false
                require_last_push_approval        = $false
                required_review_thread_resolution = $true
                allowed_merge_methods             = @("squash", "merge", "rebase")
            }
        })
        bypass_actors = @(@{ actor_id = 5; actor_type = "RepositoryRole"; bypass_mode = "always" })
    } | ConvertTo-Json -Depth 10
    $payload | gh api "repos/$Repo/rulesets" -X POST --input - | Out-Null
    Write-Host "OK ruleset '$name' instalado: PRs obligatorios hacia la rama default de $Repo." -ForegroundColor Green
    Write-Host "NOTA honesta: los admins del repo tienen bypass (el tooling sigue funcionando);" -ForegroundColor DarkGray
    Write-Host "la proteccion dura para humanos, el gate del flujo work aplica para el agente." -ForegroundColor DarkGray
    exit 0
}

if ($PR -le 0) { throw "Usa -PR <numero> (o -InstallRuleset)." }

Write-Host "=== Review gate  $Repo  PR #$PR ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Request a Copilot code review (best-effort) ────────────────────────────
# Confirming the request used to false-negative: an immediate re-query can miss the
# freshly added reviewer (eventual consistency), printing "no disponible" even when
# Copilot WAS added. Instead we trust the POST response body (its requested_reviewers
# is authoritative and immediate) and fall back to a short GET retry.
$copilotRequested = $false

function Test-CopilotPending {
    # GET the current requested reviewers; the Copilot bot shows up under .users as
    # login "Copilot". Returns $true when it is present.
    $rr = gh api "repos/$Repo/pulls/$PR/requested_reviewers" 2>$null | ConvertFrom-Json
    return [bool](@($rr.users) | Where-Object { $_.login -match '(?i)copilot' })
}

try {
    $postResp = gh api "repos/$Repo/pulls/$PR/requested_reviewers" -X POST `
        -f "reviewers[]=copilot-pull-request-reviewer[bot]" 2>$null | ConvertFrom-Json
    # A failed POST (Copilot not enabled) yields an error object with no requested_reviewers.
    if ($postResp -and (@($postResp.requested_reviewers) | Where-Object { $_.login -match '(?i)copilot' })) {
        $copilotRequested = $true
    }
} catch { }

if (-not $copilotRequested) {
    # Eventual consistency: the reviewer may take a moment to surface (also covers a
    # re-run where the bot was already requested and the POST returned no fresh body).
    foreach ($attempt in 1..3) {
        if (Test-CopilotPending) { $copilotRequested = $true; break }
        Start-Sleep -Seconds 2
    }
}

if ($copilotRequested) {
    Write-Host "  OK  Review de Copilot solicitado (reviewer pendiente confirmado)" -ForegroundColor Green
} else {
    Write-Host "  WARN Copilot code review no disponible en esta cuenta/repo." -ForegroundColor DarkYellow
    Write-Host "       Fallback obligatorio: self-review explicito de 'gh pr diff $PR' antes de mergear," -ForegroundColor DarkYellow
    Write-Host "       y si la skill second-opinion esta disponible, usala como segundo revisor." -ForegroundColor DarkYellow
}

# ── 1.5. Small-PR guard (GitHub PR BP: small, focused pull requests) ──────────
$size = gh pr view $PR --repo $Repo --json additions,deletions,changedFiles | ConvertFrom-Json
$totalLines = $size.additions + $size.deletions
Write-Host ""
Write-Host ("  Tamano del PR: {0} archivo(s), +{1}/-{2} ({3} lineas)" -f $size.changedFiles, $size.additions, $size.deletions, $totalLines) -ForegroundColor Cyan
if ($totalLines -gt $MaxLines -or $size.changedFiles -gt $MaxFiles) {
    Write-Host "  WARN PR grande (umbral: $MaxLines lineas / $MaxFiles archivos)." -ForegroundColor DarkYellow
    Write-Host "       Un PR chico se revisa mejor y mete menos bugs. Considera dividir el issue con:" -ForegroundColor DarkYellow
    Write-Host "       Board-Breakdown.ps1 -Parent <issueNum> -Tasks `"parte A`", `"parte B`"" -ForegroundColor DarkYellow
    Write-Host "       (advertencia, no bloqueo - los umbrales se ajustan con -MaxLines/-MaxFiles)" -ForegroundColor DarkGray
}

# ── 1.7. TMDL diff review (M2.2): breaking schema changes in PBIP models ──────
# Warn-only: this step never changes the gate verdict. It surfaces breaking
# semantic-model changes so the reviewer acknowledges them before merging.
$tmdlChanged = gh api "repos/$Repo/pulls/$PR/files" --paginate --jq '.[] | select(.filename | endswith(".tmdl")) | .filename' 2>$null
if ($tmdlChanged) {
    Write-Host ""
    Write-Host "  Cambios en modelo TMDL detectados - corriendo review de esquema..." -ForegroundColor Cyan
    $tmdlScript = Join-Path $PSScriptRoot "Tmdl-DiffReview.ps1"
    if (Test-Path $tmdlScript) {
        & $tmdlScript -Repo $Repo -PR $PR
    } else {
        Write-Host "  WARN Tmdl-DiffReview.ps1 no encontrado junto al gate - salteando review TMDL." -ForegroundColor DarkYellow
    }
}

# ── 2. CI checks ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Esperando checks de CI..." -ForegroundColor Cyan
$checksOk = $true
$checksOut = gh pr checks $PR --repo $Repo --watch 2>&1
$checksExit = $LASTEXITCODE
$checksText = ($checksOut | Out-String).Trim()
if ($checksText) { Write-Host $checksText }
if ($checksExit -ne 0) {
    if ($checksText -match '(?i)no checks') {
        Write-Host "  (sin checks configurados - cuenta como pass, considera /board automate)" -ForegroundColor DarkGray
    } else {
        $checksOk = $false
        Write-Host "  FAIL hay checks fallando" -ForegroundColor Red
    }
} else {
    Write-Host "  OK  checks en verde" -ForegroundColor Green
}

# ── 3. Wait for the review, then collect decision + threads ───────────────────
function Get-ReviewState {
    $q = gh api graphql -f query='
query($o:String!, $r:String!, $n:Int!) {
  repository(owner:$o, name:$r) {
    pullRequest(number:$n) {
      reviewDecision
      reviews(last:20) { nodes { author { login } state body submittedAt } }
      reviewThreads(first:50) { nodes { isResolved } }
    }
  }
}' -f "o=$($rp[0])" -f "r=$($rp[1])" -F "n=$PR" | ConvertFrom-Json
    return $q.data.repository.pullRequest
}

# NOTE: variable must NOT be named $pr - PowerShell vars are case-insensitive and it would
# collide with the [int]$PR parameter (type conversion crash).
$prState = Get-ReviewState
if ($copilotRequested) {
    Write-Host ""
    Write-Host "  Esperando el review (max $TimeoutMinutes min)..." -ForegroundColor Cyan
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $reviews = @($prState.reviews.nodes)
        if ($reviews.Count -gt 0 -and ($reviews | Where-Object { $_.author.login -match '(?i)copilot' })) { break }
        Start-Sleep -Seconds 20
        $prState = Get-ReviewState
    }
}

$reviews    = @($prState.reviews.nodes)
$unresolved = @($prState.reviewThreads.nodes | Where-Object { $_.isResolved -eq $false }).Count
$decision   = $prState.reviewDecision

Write-Host ""
Write-Host "----- RESULTADO DEL REVIEW -----" -ForegroundColor Cyan
Write-Host ("Decision      : {0}" -f ($(if ($decision) { $decision } else { "(sin reviews requeridos)" })))
Write-Host ("Reviews       : {0}" -f $reviews.Count)
foreach ($r in $reviews) {
    Write-Host ("  [{0}] {1} - {2}" -f $r.state, $r.author.login, $r.submittedAt) -ForegroundColor Yellow
    if ($r.body) { Write-Host ("    {0}" -f $r.body) }
}
Write-Host ("Hilos abiertos: {0}" -f $unresolved)
if ($unresolved -gt 0) {
    Write-Host "  Comentarios sin resolver (path:linea):" -ForegroundColor Yellow
    gh api "repos/$Repo/pulls/$PR/comments" --jq '.[] | "  \(.path):\(.line // .original_line)  [\(.user.login)] \(.body)"' 2>$null |
        Select-Object -First 30 | ForEach-Object { Write-Host $_ }
}
Write-Host "--------------------------------" -ForegroundColor Cyan
Write-Host ""

# ── 4. Verdict ─────────────────────────────────────────────────────────────────
$blockers = @()
if (-not $checksOk)                        { $blockers += "checks de CI fallando" }
if ($decision -eq "CHANGES_REQUESTED")     { $blockers += "review pide cambios (CHANGES_REQUESTED)" }
if ($unresolved -gt 0)                     { $blockers += "$unresolved hilo(s) de review sin resolver" }

if ($blockers.Count -eq 0) {
    Write-Host "GATE PASSED - seguro mergear (gh pr merge $PR --repo $Repo --squash --delete-branch)." -ForegroundColor Green
    if ($reviews.Count -eq 0) {
        Write-Host "RECUERDA: llegaron 0 reviews (solicitud aceptada no garantiza review) -" -ForegroundColor Yellow
        Write-Host "el self-review de 'gh pr diff $PR' es OBLIGATORIO antes del merge." -ForegroundColor Yellow
    }
    exit 0
} else {
    Write-Host "GATE BLOCKED:" -ForegroundColor Red
    $blockers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Atiende el feedback, push, y re-ejecuta este gate." -ForegroundColor Yellow
    exit 1
}
