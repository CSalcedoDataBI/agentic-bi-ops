<#
.SYNOPSIS
    Write a verified session handoff (/board handoff save) so work can resume in a
    fresh session days later - even on another machine.

.DESCRIPTION
    The deterministic half of `/board handoff save`. The agent composes the curated,
    already-tagged narrative (next step / done / open threads / traps / key files);
    this script does the mechanical + verifiable parts:

      1. Autofills frontmatter from git + the active `.agentic-bi-ops/sessions.json`
         entry + `gh` (issue, repo, branch, pr, board, saved, host).
      2. Injects a "Verified git state" block gathered live this run (all [V]).
      3. Computes the verified ratio ([V] claims / total tagged claims).
      4. Assembles HANDOFF.md, writes it at the repo root, rotates the previous one to
         .handoffs/<yyyyMMddTHHmmssZ>-handoff.md, and keeps both gitignored.
      5. When the session is board-linked, upserts an `[abios-handoff]` comment on the
         linked issue (the durable, cross-machine source of truth). The local file is a
         fast mirror; the issue comment is what survives a clean checkout on machine B.

    See references/handoff.md for the full design (persistence model, [V]/[?] protocol).

    Dot-source guard: set $env:ABIOS_HANDOFF_DOTSOURCE=1 before dot-sourcing to load the
    pure helpers for Pester WITHOUT the token check or any gh/git side effect.

.PARAMETER Save
    The action switch (this script currently implements save; resume is #140).

.PARAMETER NextStep
    The single concrete next step. Should be [V]/[?]-tagged by the caller.

.PARAMETER Done
    Bullet lines of what was accomplished this session (each [V]/[?]-tagged).

.PARAMETER OpenThreads
    Bullet lines of decisions/threads still open.

.PARAMETER Traps
    Bullet lines of failed approaches / traps to NOT repeat.

.PARAMETER KeyFiles
    Relevant file paths for the next session.

.PARAMETER Issue
    Linked issue number. Default: matched from sessions.json by branch, else parsed
    from an `issue-<n>-...` branch name.

.PARAMETER Repo
    owner/name. Default: derived from origin.

.PARAMETER ProjectNum
    Board number (cosmetic in the frontmatter). Default: resolved best-effort.

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Default GITHUB_TOKEN_PERSONAL.

.PARAMETER DryRun
    Print the handoff and the intended comment action without writing or posting.

.EXAMPLE
    .\Board-Handoff.ps1 -Save -NextStep "[V] Implement -Resume" -Done "[V] wrote save" -Traps "[V] docs/ is gitignored"
#>
[CmdletBinding()]
param(
    [switch]  $Save,
    [switch]  $Resume,
    [string]  $NextStep = "",
    [string[]]$Done = @(),
    [string[]]$OpenThreads = @(),
    [string[]]$Traps = @(),
    [string[]]$KeyFiles = @(),
    [int]     $Issue = 0,
    [string]  $Repo = "",
    [string]  $Owner = "",
    [int]     $ProjectNum = 0,
    [string]  $TokenVar = "GITHUB_TOKEN_PERSONAL",
    [switch]  $DryRun
)

# ==============================================================================
# Pure helpers (unit-testable; no gh/git/network, no side effects)
# ==============================================================================

# The comment marker that identifies OUR handoff comment on the issue, so save can
# find-and-edit it instead of piling up new comments.
$script:HandoffMarker = "<!-- abios-handoff -->"

# Parse the issue number out of a work branch name: issue-<n>-slug -> <n>.
function Get-HandoffBranchIssue([string]$branch) {
    if ($branch -match '^issue-(\d+)') { return [int]$Matches[1] }
    return 0
}

# Colon-free basic-format ISO-8601 UTC stamp for archive filenames (':' is invalid
# on Windows). Takes a DateTime so tests are deterministic.
function New-HandoffArchiveName([datetime]$when) {
    return ($when.ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + "-handoff.md")
}

# RFC3339 UTC (always Z) for the frontmatter `saved` field.
function Get-HandoffStamp([datetime]$when) {
    return $when.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Count [V] verified vs [?] unverified claim tags and return "N/M" (verified / total
# tagged). Only LINE-LEADING tags count (a claim line starts with the tag, optionally
# after a "- " bullet / indentation) - so a [V] or [?] appearing mid-line, e.g. inside
# a gathered commit message, is NOT miscounted as a claim. "0/0" when nothing is tagged.
function Get-HandoffVerifiedRatio([string[]]$lines) {
    $text = ($lines -join "`n")
    $v = ([regex]::Matches($text, '(?m)^\s*(?:-\s*)?\[V\]')).Count
    $q = ([regex]::Matches($text, '(?m)^\s*(?:-\s*)?\[\?\]')).Count
    return "$v/$($v + $q)"
}

# Serialize an ordered frontmatter hashtable to a YAML block (--- ... ---).
function ConvertTo-HandoffFrontmatter([System.Collections.Specialized.OrderedDictionary]$fields) {
    $lines = @("---")
    foreach ($k in $fields.Keys) {
        $val = $fields[$k]
        if ($null -eq $val -or "$val" -eq "") { $val = "null" }
        $lines += "${k}: $val"
    }
    $lines += "---"
    return ($lines -join "`n")
}

# Assemble the full HANDOFF.md markdown from the frontmatter + gathered git block +
# the caller's curated sections. Sections with no content are omitted.
function Format-HandoffMarkdown {
    param(
        [string]  $Frontmatter,
        [string]  $Heading,
        [string]  $GitBlock,
        [string]  $NextStep,
        [string[]]$Done,
        [string[]]$OpenThreads,
        [string[]]$Traps,
        [string[]]$KeyFiles
    )
    $out = @($Frontmatter, "", "# $Heading", "")
    if ($NextStep) { $out += @("## Next concrete step", $NextStep, "") }
    if ($GitBlock) { $out += @("## Verified git state", $GitBlock, "") }
    $sections = [ordered]@{
        "Done this session"            = $Done
        "Open threads / decisions pending" = $OpenThreads
        "Traps / failed approaches (do NOT repeat)" = $Traps
        "Key files"                    = $KeyFiles
    }
    foreach ($title in $sections.Keys) {
        $items = @($sections[$title] | Where-Object { $_ -and "$_".Trim() -ne "" })
        if ($items.Count) {
            $out += "## $title"
            $out += ($items | ForEach-Object { if ($_ -match '^\s*-') { $_ } else { "- $_" } })
            $out += ""
        }
    }
    return (($out -join "`n").TrimEnd() + "`n")
}

# Idempotently ensure the given patterns are present in a .gitignore body. Returns
# the (possibly unchanged) full body.
function Add-GitignoreEntries([string]$body, [string[]]$patterns) {
    $existing = @($body -split "`r?`n")
    $missing = @($patterns | Where-Object { $p = $_; -not ($existing | Where-Object { $_.Trim() -eq $p }) })
    if (-not $missing.Count) { return $body }
    $trimmed = $body.TrimEnd("`r", "`n")
    $block = ($missing -join "`n")
    if ($trimmed) { return "$trimmed`n$block`n" }
    return "$block`n"
}

# -- Resume-side pure helpers (parse a handoff back out) ------------------------

# Extract the HANDOFF.md content from an issue comment body: the text between the
# ```md opening fence and its closing ``` fence. Returns "" when there is no fence.
function Get-HandoffBodyFromComment([string]$commentBody) {
    $lines = @($commentBody -split "`r?`n")
    $start = -1; $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($start -lt 0) {
            if ($lines[$i].Trim() -eq '```md') { $start = $i + 1 }
        } elseif ($lines[$i].Trim() -eq '```') { $end = $i; break }
    }
    if ($start -lt 0 -or $end -lt 0 -or $end -le $start) { return "" }
    return (($lines[$start..($end - 1)]) -join "`n")
}

# Read a single frontmatter field from a handoff markdown (the first `key: value`
# inside the leading --- ... --- block). Returns "" when absent.
function Get-HandoffFrontmatterField([string]$markdown, [string]$key) {
    $lines = @($markdown -split "`r?`n")
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return "" }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        if ($lines[$i] -match "^\s*$([regex]::Escape($key))\s*:\s*(.+?)\s*$") { return $Matches[1].Trim() }
    }
    return ""
}

# Return the bullet lines under a `## <title>` section (until the next `## ` or EOF).
# Used to carry unresolved traps forward into the resumed session.
function Get-HandoffSection([string]$markdown, [string]$title) {
    $lines = @($markdown -split "`r?`n")
    $out = @(); $inSection = $false
    foreach ($ln in $lines) {
        if ($ln -match '^\s*##\s+(.+?)\s*$') {
            $inSection = ($Matches[1].Trim() -eq $title.Trim())
            continue
        }
        if ($inSection -and $ln.Trim() -ne "") { $out += $ln }
    }
    return $out
}

# ==============================================================================
# Main entry. Dot-source guard: the test harness sets ABIOS_HANDOFF_DOTSOURCE to
# load the helpers above without running any of the side-effecting code below.
# ==============================================================================
if ($env:ABIOS_HANDOFF_DOTSOURCE) { return }

$ErrorActionPreference = "Stop"

if ($Save -and $Resume) { throw "Pass either -Save or -Resume, not both." }
if (-not ($Save -or $Resume)) { throw "Pass an action: -Save (snapshot) or -Resume (rehydrate)." }

if (-not $env:GH_TOKEN) { $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User") }
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

# -- Resolve repo / branch -----------------------------------------------------
if (-not $Repo) {
    $originUrl = git remote get-url origin 2>$null
    if ($originUrl -match 'github\.com[/:]([^/]+)/([^/.]+)') { $Repo = "$($Matches[1])/$($Matches[2])" }
}
if (-not $Repo) { throw "Could not derive the repo from origin - pass -Repo owner/name." }
if (-not $Owner) { $Owner = ($Repo -split "/")[0] }

$branch = (git branch --show-current 2>$null)
if (-not $branch) { $branch = "(detached)" }

# -- Session registry lookup (shared .agentic-bi-ops/ next to the main clone) ---
function Get-AbiosSessionsPath {
    $common = git rev-parse --git-common-dir 2>$null
    if (-not $common) { return $null }
    try { $root = Split-Path (Resolve-Path $common).Path -Parent } catch { return $null }
    return (Join-Path (Join-Path $root ".agentic-bi-ops") "sessions.json")
}
$session = $null
$sp = Get-AbiosSessionsPath
if ($sp -and (Test-Path $sp)) {
    try {
        $entries = @(Get-Content $sp -Raw | ConvertFrom-Json)
        $session = @($entries | Where-Object { $_.branch -eq $branch }) | Select-Object -First 1
    } catch { $session = $null }
}

# -- Resolve the linked issue --------------------------------------------------
if ($Issue -le 0 -and $session) { $Issue = [int]$session.issue }
if ($Issue -le 0)               { $Issue = Get-HandoffBranchIssue $branch }

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { throw "Not inside a git working tree." }
$handoffPath = Join-Path $repoRoot "HANDOFF.md"
$archiveDir  = Join-Path $repoRoot ".handoffs"

# ==============================================================================
# RESUME - read the latest handoff back, regenerate the local mirror, re-verify
# the [V] anchors, surface unresolved traps, and offer to continue.
# ==============================================================================
if ($Resume) {
    Write-Host "=== /board handoff resume  ($Repo)  branch $branch ===" -ForegroundColor Cyan
    Write-Host ""

    # Source of truth = the [abios-handoff] comment on the linked issue (cross-machine).
    $body = ""; $source = ""
    if ($Issue -gt 0) {
        try {
            $comments = gh api --paginate "repos/$Repo/issues/$Issue/comments?per_page=100" 2>$null | ConvertFrom-Json
            $marker = @($comments | Where-Object { $_.body -like "*$script:HandoffMarker*" }) | Select-Object -Last 1
            if ($marker) {
                $body = Get-HandoffBodyFromComment $marker.body
                if ($body) { $source = "issue comment on $Repo#$Issue" }
            }
        } catch { $body = "" }
    }
    # Fallback: the local mirror (offline / no linked issue).
    if (-not $body -and (Test-Path $handoffPath)) {
        $body = Get-Content $handoffPath -Raw
        $source = "local HANDOFF.md"
    }
    if (-not $body) {
        throw "No handoff found$(if ($Issue -gt 0) { " for $Repo#$Issue" }) - no [abios-handoff] comment and no local HANDOFF.md."
    }

    # Regenerate the local mirror when the source was the remote comment (machine B).
    if ($source -ne "local HANDOFF.md") {
        if ($DryRun) {
            Write-Host "DRY-RUN - would regenerate local HANDOFF.md from the $source." -ForegroundColor Yellow
        } else {
            Set-Content -Path $handoffPath -Value $body -Encoding UTF8 -NoNewline
            $gitignorePath = Join-Path $repoRoot ".gitignore"
            $giBody = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }
            $giNew  = Add-GitignoreEntries $giBody @("/HANDOFF.md", "/.handoffs/")
            if ($giNew -ne $giBody) { Set-Content -Path $gitignorePath -Value $giNew -Encoding UTF8 -NoNewline }
            Write-Host "  OK  Local HANDOFF.md regenerated from the $source" -ForegroundColor DarkGray
        }
    }

    Write-Host "  Source : $source" -ForegroundColor DarkCyan
    $savedAt = Get-HandoffFrontmatterField $body "saved"
    $verOf   = Get-HandoffFrontmatterField $body "verified"
    if ($savedAt) { Write-Host "  Saved  : $savedAt  (verified $verOf)" -ForegroundColor DarkCyan }
    Write-Host ""
    Write-Host $body
    Write-Host ""

    # Re-verify the [V] anchors (branch + PR) still hold; report drift.
    $drift = @()
    $hoBranch = Get-HandoffFrontmatterField $body "branch"
    if ($hoBranch -and $hoBranch -ne "null") {
        git rev-parse --verify --quiet "refs/heads/$hoBranch" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $drift += "branch '$hoBranch' no longer exists locally (deleted after merge, or needs a fetch)."
        } elseif ($branch -ne $hoBranch) {
            $drift += "you are on '$branch'; the handoff was saved on '$hoBranch' (git checkout $hoBranch to continue there)."
        }
    }
    $hoPr = Get-HandoffFrontmatterField $body "pr"
    if ($hoPr -and $hoPr -ne "null") {
        try {
            $prState = (gh pr view $hoPr --repo $Repo --json state 2>$null | ConvertFrom-Json).state
            if ($prState -and $prState -ne "OPEN") { $drift += "PR #$hoPr is now $prState (the work may already be merged/closed)." }
        } catch { }
    }
    if ($drift.Count) {
        Write-Host "  DRIFT since the handoff was saved:" -ForegroundColor Yellow
        $drift | ForEach-Object { Write-Host "    ! $_" -ForegroundColor Yellow }
        Write-Host ""
    }

    # Carry unresolved traps forward, front and center.
    $traps = Get-HandoffSection $body "Traps / failed approaches (do NOT repeat)"
    if ($traps.Count) {
        Write-Host "  CARRY FORWARD - traps to NOT repeat:" -ForegroundColor Magenta
        $traps | ForEach-Object { Write-Host "    $_" -ForegroundColor Magenta }
        Write-Host ""
    }

    if ($Issue -gt 0) {
        Write-Host "Continue this work with:  /board work -> Start #$Issue  (or: git checkout $hoBranch)" -ForegroundColor Cyan
    }
    return
}

# -- Resolve the open PR for this branch (repo-consistent form) -----------------
$pr = $null
try {
    $prJson = gh pr list --repo $Repo --head $branch --state open --json number 2>$null | ConvertFrom-Json
    if ($prJson -and $prJson.Count) { $pr = [int]$prJson[0].number }
} catch { $pr = $null }

# -- Resolve the board number (best-effort, cosmetic) --------------------------
if ($ProjectNum -le 0) {
    try {
        $resolved = & (Join-Path $PSScriptRoot "Resolve-Board.ps1") -Owner $Owner -Repo $Repo -CreateIfMissing:$false 2>$null
        if ($resolved) { $ProjectNum = [int]($resolved | Select-Object -Last 1) }
    } catch { $ProjectNum = 0 }
}

# -- Live-verified git state (every line here is genuinely [V]) -----------------
$gitStatus = @(git status --porcelain 2>$null)
$dirty     = if ($gitStatus.Count) { "$($gitStatus.Count) uncommitted change(s)" } else { "clean" }
$lastLog   = @(git log --oneline -5 2>$null)
$gitBlockLines = @(
    "[V] Branch: $branch"
    "[V] Working tree: $dirty"
    "[V] Linked issue: $(if ($Issue -gt 0) { "#$Issue" } else { 'none' }) | Open PR: $(if ($pr) { "#$pr" } else { 'none' })"
    "[V] Recent commits:"
) + @($lastLog | ForEach-Object { "    - $_" })
$gitBlock = ($gitBlockLines -join "`n")

# -- Assemble frontmatter ------------------------------------------------------
$now = Get-Date
$allTagged = @($NextStep) + $Done + $OpenThreads + $Traps + $gitBlockLines
$fm = [ordered]@{
    issue    = $(if ($Issue -gt 0) { $Issue } else { "null" })
    repo     = $Repo
    branch   = $branch
    pr       = $(if ($pr) { $pr } else { "null" })
    board    = $(if ($ProjectNum -gt 0) { $ProjectNum } else { "null" })
    saved    = Get-HandoffStamp $now
    host     = $env:COMPUTERNAME
    verified = Get-HandoffVerifiedRatio $allTagged
}
$frontmatter = ConvertTo-HandoffFrontmatter $fm

$heading = if ($Issue -gt 0) { "Handoff - #$Issue" } else { "Handoff - $branch" }
$markdown = Format-HandoffMarkdown -Frontmatter $frontmatter -Heading $heading -GitBlock $gitBlock `
    -NextStep $NextStep -Done $Done -OpenThreads $OpenThreads -Traps $Traps -KeyFiles $KeyFiles

# ($repoRoot / $handoffPath / $archiveDir were resolved above, shared with resume.)
Write-Host "=== /board handoff save  ($Repo)  branch $branch ===" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY-RUN - would write $handoffPath (verified $($fm.verified)):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host $markdown
    Write-Host ""
    if ($Issue -gt 0) {
        Write-Host "DRY-RUN - would upsert the [abios-handoff] comment on $Repo#$Issue." -ForegroundColor Yellow
    } else {
        Write-Host "DRY-RUN - no linked issue -> local HANDOFF.md only (consider committing it for portability)." -ForegroundColor Yellow
    }
    return
}

# -- Rotate the previous handoff into .handoffs/ -------------------------------
if (Test-Path $handoffPath) {
    if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Force $archiveDir | Out-Null }
    $archiveName = New-HandoffArchiveName $now
    Move-Item -Force $handoffPath (Join-Path $archiveDir $archiveName)
    Write-Host "  OK  Previous handoff archived -> .handoffs/$archiveName" -ForegroundColor DarkGray
}

# -- Write the new HANDOFF.md --------------------------------------------------
Set-Content -Path $handoffPath -Value $markdown -Encoding UTF8 -NoNewline
Write-Host "  OK  HANDOFF.md written (verified $($fm.verified))" -ForegroundColor Green

# -- Keep the mirror + archive gitignored --------------------------------------
$gitignorePath = Join-Path $repoRoot ".gitignore"
$giBody = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }
$giNew  = Add-GitignoreEntries $giBody @("/HANDOFF.md", "/.handoffs/")
if ($giNew -ne $giBody) {
    Set-Content -Path $gitignorePath -Value $giNew -Encoding UTF8 -NoNewline
    Write-Host "  OK  .gitignore updated (HANDOFF.md, .handoffs/)" -ForegroundColor DarkGray
}

# -- Upsert the durable [abios-handoff] comment on the linked issue -------------
if ($Issue -gt 0) {
    # Build via a here-string with a fence VARIABLE (no fragile backtick escaping),
    # and carry both the hidden HTML marker (for exact find) and the visible
    # [abios-handoff] tag (matches the spec / aids discovery).
    $fence = '```'
    $commentBody = @"
$script:HandoffMarker
**[abios-handoff]** session handoff - upserted by /board handoff save.

${fence}md
$markdown
${fence}
_Last saved $($fm.saved)._
"@
    # --paginate so the marker is found even on issues with >100 comments (else a
    # missed marker would post a DUPLICATE instead of editing the existing one).
    $existingId = $null
    try {
        $comments = gh api --paginate "repos/$Repo/issues/$Issue/comments?per_page=100" 2>$null | ConvertFrom-Json
        $existingId = (@($comments | Where-Object { $_.body -like "*$script:HandoffMarker*" }) | Select-Object -Last 1).id
    } catch { $existingId = $null }

    try {
        if ($existingId) {
            $commentBody | gh api --method PATCH "repos/$Repo/issues/comments/$existingId" -F body=@- 2>$null | Out-Null
            Write-Host "  OK  Handoff comment updated on $Repo#$Issue (durable source of truth)" -ForegroundColor Green
        } else {
            $commentBody | gh issue comment $Issue --repo $Repo --body-file - 2>$null | Out-Null
            Write-Host "  OK  Handoff comment posted on $Repo#$Issue (durable source of truth)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  WARN could not upsert the issue comment - the local HANDOFF.md is still written." -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "Resume later with:  Board-Handoff.ps1 -Resume  (reads $Repo#$Issue - even on another machine)" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "  No linked issue - wrote a LOCAL HANDOFF.md only. It is gitignored, so to use it on" -ForegroundColor DarkYellow
    Write-Host "  another machine either copy it out of the repo, or force-commit it with" -ForegroundColor DarkYellow
    Write-Host "  'git add -f HANDOFF.md' (there is no board issue to carry it for you)." -ForegroundColor DarkYellow
}
