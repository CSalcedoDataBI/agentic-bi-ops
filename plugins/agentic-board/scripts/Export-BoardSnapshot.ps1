<#  Export-BoardSnapshot.ps1 - render a Projects board as a Markdown table (a publishable snapshot).
    Requires $env:GH_TOKEN (via gh-account). ASCII-only source.
    Usage: ./Export-BoardSnapshot.ps1 -Number 13 -Owner CSalcedoDataBI -OutFile snapshot.md  #>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$Number,
  [Parameter(Mandatory)][string]$Owner,
  [string]$OutFile
)
$ErrorActionPreference = 'Stop'
# gh fails by exit code only, and a native command exiting non-zero does not throw (#303).
# Unchecked, a 401 made this publish a snapshot reading "0 of 0 tracked items done." - a
# document that looks like a finished board rather than a failed read.
. (Join-Path $PSScriptRoot 'Invoke-Gh.ps1')

$resp  = Invoke-Gh -GhArgs @('project', 'item-list', "$Number", '--owner', $Owner, '--format', 'json', '--limit', '500') `
                   -What "leer los items del board #$Number de $Owner" -Json -Retries 2
$items = @($resp.items)

$rank  = @{ 'Backlog' = 0; 'In Progress' = 1; 'In Review' = 2; 'Done' = 3 }
$sorted = $items | Sort-Object `
  @{ Expression = { if ($rank.ContainsKey([string]$_.status)) { $rank[[string]$_.status] } else { 9 } } },
  @{ Expression = { $_.content.number } }

$done  = ($items | Where-Object { $_.status -eq 'Done' }).Count
$total = $items.Count

$lines = @()
$lines += "_$done of $total tracked items done._"
$lines += ""
$lines += "| Status | Item | Issue |"
$lines += "|--------|------|-------|"
foreach ($it in $sorted) {
  $s = if ($it.status) { $it.status } else { '-' }
  $t = ($it.title -replace '\|', '\|')
  $n = $it.content.number
  $u = $it.content.url
  $lines += ("| {0} | {1} | [#{2}]({3}) |" -f $s, $t, $n, $u)
}
$out = $lines -join "`n"

if ($OutFile) { $out | Out-File $OutFile -Encoding UTF8; Write-Host "Snapshot written: $OutFile" }
else { $out }
