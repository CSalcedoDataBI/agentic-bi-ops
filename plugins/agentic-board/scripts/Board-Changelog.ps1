<#
.SYNOPSIS
    Generate a Keep-a-Changelog block from closed board items (M4.2).

.DESCRIPTION
    GitHub Projects best practice: the board is the single source of truth for
    what shipped. This script turns the board's Done issues into a CHANGELOG
    version block, grouped into Keep-a-Changelog sections by the board's Type
    field (falling back to labels):

      Feature                  -> ### Added
      Bug                      -> ### Fixed
      Docs / Refactor / Chore  -> ### Changed
      (no Type) -> infer from labels: bug -> Fixed; docs/refactor/chore ->
                   Changed; otherwise Added.

    Which issues are included (both filters apply, so already-shipped work is
    never re-listed):
      1. closedAt >= -Since  (default: the date of the most recent CHANGELOG
         entry, so only work since the last release is considered), and
      2. the issue number is NOT already cited as (#<n>) anywhere in the
         existing CHANGELOG.

    Prints the block to stdout. With -Write it is inserted at the top of the
    CHANGELOG (just under the "# Changelog" header), ready to commit.

    Linked PRs / merge state are not needed here - a Done+closed issue is what
    "shipped" means on this board.

.PARAMETER Owner
    GitHub user that owns the board. Default CSalcedoDataBI.

.PARAMETER ProjectNum
    Projects v2 number. Default 13.

.PARAMETER Repo
    owner/name - only issues from this repo are included. Default: origin.

.PARAMETER Version
    Version string for the header. Default: version from the plugin.json under
    plugins/*/.claude-plugin/, else 0.0.0.

.PARAMETER Date
    ISO date for the header. Default: today.

.PARAMETER Since
    Only issues closed on/after this ISO date. Default: the date of the most
    recent existing CHANGELOG entry (## [x] - YYYY-MM-DD).

.PARAMETER Write
    Insert the block at the top of the CHANGELOG instead of only printing it.

.PARAMETER ChangelogPath
    Path to the changelog file. Default: CHANGELOG.md in the cwd.

.PARAMETER TokenVar
    Windows USER env var holding the PAT. Default GITHUB_TOKEN_PERSONAL.

.EXAMPLE
    .\Board-Changelog.ps1 -ProjectNum 13
    .\Board-Changelog.ps1 -ProjectNum 13 -Version 0.11.0 -Write
    .\Board-Changelog.ps1 -ProjectNum 13 -Since 2026-06-01
#>
[CmdletBinding()]
param(
    [string]$Owner         = "CSalcedoDataBI",
    [int]   $ProjectNum    = 13,
    [string]$Repo          = "",
    [string]$Version       = "",
    [string]$Date          = "",
    [string]$Since         = "",
    [switch]$Write,
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$TokenVar      = "GITHUB_TOKEN_PERSONAL"
)

$ErrorActionPreference = "Stop"

if (-not $env:GH_TOKEN) {
    $env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($TokenVar, "User")
}
if (-not $env:GH_TOKEN) { throw "$TokenVar not set in Windows USER environment (and GH_TOKEN empty)." }

# ── Resolve repo (filter issues to it) ────────────────────────────────────────
if (-not $Repo) {
    $originUrl = git remote get-url origin 2>$null
    if ($originUrl -match 'github\.com[/:]([^/]+)/([^/.]+)') { $Repo = "$($Matches[1])/$($Matches[2])" }
}
if (-not $Repo) { throw "No pude derivar el repo del origin - pasa -Repo owner/name." }

# ── Existing CHANGELOG: cited issue numbers + last entry date ─────────────────
$alreadyCited = @{}
$lastEntryDate = $null
if (Test-Path $ChangelogPath) {
    $clText = Get-Content $ChangelogPath -Raw
    foreach ($m in [regex]::Matches($clText, '#(\d+)')) { $alreadyCited[[int]$m.Groups[1].Value] = $true }
    $dm = [regex]::Match($clText, '##\s*\[[^\]]+\]\s*-\s*(\d{4}-\d{2}-\d{2})')
    if ($dm.Success) { $lastEntryDate = $dm.Groups[1].Value }
}

if (-not $Since) { $Since = $lastEntryDate }
# ISO dates only; parse invariant so a dd/MM machine culture doesn't choke.
$sinceDt = if ($Since) {
    [datetime]::Parse($Since, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal)
} else { [datetime]::MinValue }

# ── Defaults for Version / Date ───────────────────────────────────────────────
if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM-dd') }
if (-not $Version) {
    $pj = Get-ChildItem -Path . -Recurse -Filter plugin.json -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -match '\.claude-plugin' } | Select-Object -First 1
    if ($pj) {
        $vm = [regex]::Match((Get-Content $pj.FullName -Raw), '"version"\s*:\s*"([^"]+)"')
        if ($vm.Success) { $Version = $vm.Groups[1].Value }
    }
    if (-not $Version) { $Version = "0.0.0" }
}

# ── Read board items (issue content + Type single-select) ─────────────────────
$data = gh api graphql -f query='
query($owner:String!, $num:Int!) {
  user(login:$owner) {
    projectV2(number:$num) {
      id
      items(first:100) {
        nodes {
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
              number title state closedAt url
              labels(first:15) { nodes { name } }
            }
          }
        }
      }
    }
  }
}' -F "owner=$Owner" -F "num=$ProjectNum" | ConvertFrom-Json

if (-not $data.data.user.projectV2.id) {
    throw "No pude resolver el board #$ProjectNum de $Owner (revisa cuenta / scope 'project')."
}
$nodes = $data.data.user.projectV2.items.nodes

# ── Select + bucket ───────────────────────────────────────────────────────────
$sections = [ordered]@{ Added = @(); Changed = @(); Fixed = @() }

function Resolve-Section($type, $labels) {
    switch ($type) {
        'Feature'  { return 'Added' }
        'Bug'      { return 'Fixed' }
        'Docs'     { return 'Changed' }
        'Refactor' { return 'Changed' }
        'Chore'    { return 'Changed' }
    }
    if ($labels -contains 'bug')                                              { return 'Fixed' }
    if ($labels -contains 'docs' -or $labels -contains 'refactor' -or $labels -contains 'chore') { return 'Changed' }
    return 'Added'
}

$skippedRepo = 0; $skippedCited = 0; $skippedOld = 0; $included = 0
foreach ($n in $nodes) {
    $c = $n.content
    if ($c.__typename -ne 'Issue') { continue }
    if ($c.state -ne 'CLOSED') { continue }
    if ($c.url -notlike "*/$Repo/issues/*") { $skippedRepo++; continue }
    if ($alreadyCited.ContainsKey([int]$c.number)) { $skippedCited++; continue }
    if ($c.closedAt) {
        # ConvertFrom-Json already coerces the ISO string to [datetime]; only
        # parse (invariant) if it arrived as a string.
        $closed = if ($c.closedAt -is [datetime]) { $c.closedAt }
                  else { [datetime]::Parse([string]$c.closedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
        if ($closed -lt $sinceDt) { $skippedOld++; continue }
    }

    $type   = ($n.fieldValues.nodes | Where-Object { $_.field.name -eq 'Type' }).name
    $labels = @($c.labels.nodes.name | Where-Object { $_ } | ForEach-Object { $_.ToLower() })
    $sec    = Resolve-Section $type $labels
    $sections[$sec] += "- **$($c.title)** (#$($c.number))"
    $included++
}

# ── Build the block ───────────────────────────────────────────────────────────
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("## [$Version] - $Date")
$any = $false
foreach ($secName in $sections.Keys) {
    $lines = $sections[$secName]
    if ($lines.Count -eq 0) { continue }
    $any = $true
    [void]$sb.AppendLine("### $secName")
    foreach ($l in ($lines | Sort-Object)) { [void]$sb.AppendLine($l) }
}
$block = $sb.ToString().TrimEnd()

Write-Host "=== Board-Changelog  $Repo  board #$ProjectNum ===" -ForegroundColor Cyan
Write-Host ("  Since: {0}  |  incluidos: {1}  |  omitidos: {2} otro-repo, {3} ya-citados, {4} anteriores" -f `
    ($(if ($Since) { $Since } else { "(todo)" })), $included, $skippedRepo, $skippedCited, $skippedOld) -ForegroundColor DarkGray
Write-Host ""

if (-not $any) {
    Write-Host "  Sin issues Done nuevos para changelog (nada desde $Since que no este ya citado)." -ForegroundColor Green
    exit 0
}

Write-Host $block
Write-Host ""

# ── Optionally write into the CHANGELOG ───────────────────────────────────────
if ($Write) {
    if (-not (Test-Path $ChangelogPath)) { throw "No existe $ChangelogPath - no puedo insertar." }
    $orig = Get-Content $ChangelogPath -Raw
    # Insert right after the top "# Changelog" header (and its trailing blank line).
    if ($orig -match '(?s)^(#\s+Changelog\s*\r?\n)(\r?\n)?(.*)$') {
        $header = $Matches[1]
        $rest   = $Matches[3]
        $newText = $header + "`n" + $block + "`n`n" + $rest
    } else {
        # No recognizable header - just prepend.
        $newText = $block + "`n`n" + $orig
    }
    Set-Content -Path $ChangelogPath -Value $newText -NoNewline
    Write-Host "OK  bloque insertado en $ChangelogPath (revisa y commitea)." -ForegroundColor Green
}
