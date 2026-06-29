<#  Resolve-Board.ps1 - find-or-reuse the board for a repo; create only if none exists.
    Prevents the "new duplicate board every time" bug. Returns the project NUMBER on stdout.
    Requires $env:GH_TOKEN (via gh-account).
    Usage: $num = & ./Resolve-Board.ps1 -Owner CSalcedoDataBI -Repo CSalcedoDataBI/agentic-bi-ops
    NOTE: source is pure ASCII; the em-dash in the canonical title is built at runtime so the file
          parses under Windows PowerShell 5.1 regardless of file encoding.  #>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Owner,
  [Parameter(Mandatory)][string]$Repo,     # owner/name
  [string]$Title,
  [bool]$CreateIfMissing = $true
)
$ErrorActionPreference = 'Stop'
$dash     = [char]0x2014                       # em-dash, built in code (no non-ASCII in source)
$repoName = $Repo.Split('/')[-1]
if (-not $Title) { $Title = "$repoName $dash Roadmap" }

$projects   = (gh project list --owner $Owner --format json | ConvertFrom-Json).projects
$candidates = $projects | Where-Object { $_.title -notmatch '(?i)backup' }

$match = $candidates | Where-Object { $_.title -eq $Title } | Select-Object -First 1
if (-not $match) { $match = $candidates | Where-Object { $_.title -like "*$repoName*" } | Select-Object -First 1 }

if ($match) {
  Write-Host ("REUSE existing board #{0}: '{1}'" -f $match.number, $match.title) -ForegroundColor Green
  return $match.number
}
if (-not $CreateIfMissing) { Write-Host "No board found for $Repo (CreateIfMissing=false)"; return $null }

$num = (gh project create --owner $Owner --title $Title --format json | ConvertFrom-Json).number
gh project link $num --owner $Owner --repo $Repo | Out-Null
gh project edit $num --owner $Owner --description "Roadmap + issue tracking for $Repo. Anchored to that repo." | Out-Null
Write-Host ("CREATED board #{0}: '{1}' (linked to {2})" -f $num, $Title, $Repo) -ForegroundColor Yellow
return $num
