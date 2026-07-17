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
# gh fails by exit code only, and a native command exiting non-zero does not throw (#303).
# This script is the LAST line of defence before a delete, so it must never mistake a 401
# for an empty board and write a plausible-looking empty snapshot.
. (Join-Path $PSScriptRoot 'Invoke-Gh.ps1')
if (-not $BackupDir) {
  $BackupDir = if ($env:ABIOS_BACKUP_DIR) { $env:ABIOS_BACKUP_DIR } else { Join-Path (Get-AbiosStateDir -Root $HOME) 'backups' }
}
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

# READ EVERYTHING FIRST, and only then write. -RawJson validates the body as JSON but hands
# back gh's original text: a backup is persisted verbatim, so round-tripping it through
# ConvertTo-Json would reshape it (and -Depth would quietly truncate it).
# Read-then-write also means a failure on the third read cannot leave two files behind that
# look like a partial backup nobody labelled as one.
$meta   = Invoke-Gh -GhArgs @('project', 'view',       "$Number", '--owner', $Owner, '--format', 'json') `
                    -What "leer el board #$Number de $Owner" -RawJson -Retries 2
$fields = Invoke-Gh -GhArgs @('project', 'field-list', "$Number", '--owner', $Owner, '--format', 'json') `
                    -What "leer los campos del board #$Number" -RawJson -Retries 2
$items  = Invoke-Gh -GhArgs @('project', 'item-list',  "$Number", '--owner', $Owner, '--format', 'json', '--limit', '1000') `
                    -What "leer los items del board #$Number" -RawJson -Retries 2

$title  = ($meta | ConvertFrom-Json).title
if (-not $title) { throw "El board #$Number no devolvio un titulo - no hago un backup de algo que no pude leer." }
$safe   = ($title -replace '[^\w\-]+', '_').Trim('_')
$base   = Join-Path $BackupDir ("{0}_{1}" -f $safe, $stamp)

$meta   | Out-File ("$base.project.json") -Encoding UTF8
$fields | Out-File ("$base.fields.json")  -Encoding UTF8
$items  | Out-File ("$base.items.json")   -Encoding UTF8

# Verify what was WRITTEN, not what we meant to write. The point of this script is that the
# file is there on the day someone needs it, and an empty file that reports "Backup OK" is
# the one failure that is only ever discovered when it is already too late.
foreach ($f in @("$base.project.json", "$base.fields.json", "$base.items.json")) {
    if (-not (Test-Path $f))            { throw "El backup no se escribio: $f" }
    if ((Get-Item $f).Length -eq 0)     { throw "El backup quedo VACIO: $f" }
}

# restorable live clone (fields/views + draft issues)
$cloneTitle = "$title $dash backup $stamp"
Invoke-Gh -GhArgs @('project', 'copy', "$Number", '--source-owner', $Owner, '--target-owner', $Owner, '--drafts', '--title', $cloneTitle) `
          -What "clonar el board #$Number" -Retries 2 | Out-Null

Write-Host "Backup OK:"
Write-Host ("  JSON snapshot: {0}.project.json (+ .fields.json, .items.json)" -f $base)
Write-Host ("  Live clone   : '{0}' in projects of {1}" -f $cloneTitle, $Owner)
