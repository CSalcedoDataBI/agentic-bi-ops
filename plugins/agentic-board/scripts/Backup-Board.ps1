<#  Backup-Board.ps1 - make a COMPLETE backup of a Projects board. ALWAYS run before delete.
    Writes a JSON snapshot (project meta + fields + items) AND creates a restorable live clone.
    Requires $env:GH_TOKEN (via gh-account). Backups go to $env:ABIOS_BACKUP_DIR or ~/.agentic-board/backups.
    Usage: ./Backup-Board.ps1 -Number 13 -Owner CSalcedoDataBI
    NOTE: source is pure ASCII; the em-dash is built at runtime for Windows PowerShell 5.1 safety.  #>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$Number,
  [Parameter(Mandatory)][string]$Owner,
  [string]$BackupDir
)
$ErrorActionPreference = 'Stop'
$dash = [char]0x2014
# The single resolver for the internal state dir (new name + migration + fallback).
. (Join-Path $PSScriptRoot 'Get-AbiosStateDir.ps1')
if (-not $BackupDir) {
  $BackupDir = if ($env:ABIOS_BACKUP_DIR) { $env:ABIOS_BACKUP_DIR } else { Join-Path (Get-AbiosStateDir -Root $HOME) 'backups' }
}
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$meta   = gh project view      $Number --owner $Owner --format json
$fields = gh project field-list $Number --owner $Owner --format json
$items  = gh project item-list $Number --owner $Owner --format json --limit 1000

$title  = ($meta | ConvertFrom-Json).title
$safe   = ($title -replace '[^\w\-]+', '_').Trim('_')
$base   = Join-Path $BackupDir ("{0}_{1}" -f $safe, $stamp)

$meta   | Out-File ("$base.project.json") -Encoding UTF8
$fields | Out-File ("$base.fields.json")  -Encoding UTF8
$items  | Out-File ("$base.items.json")   -Encoding UTF8

# restorable live clone (fields/views + draft issues)
$cloneTitle = "$title $dash backup $stamp"
gh project copy $Number --source-owner $Owner --target-owner $Owner --drafts --title $cloneTitle | Out-Null

Write-Host "Backup OK:"
Write-Host ("  JSON snapshot: {0}.project.json (+ .fields.json, .items.json)" -f $base)
Write-Host ("  Live clone   : '{0}' in projects of {1}" -f $cloneTitle, $Owner)
