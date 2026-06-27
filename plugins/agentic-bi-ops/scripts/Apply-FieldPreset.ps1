<#  Apply-FieldPreset.ps1 — idempotently create the fields of a preset on a Projects board.
    Requires $env:GH_TOKEN already set (via the gh-account skill).
    Usage:
      $env:GH_TOKEN = <token>
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -Lang en
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -PresetPath custom.json  #>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$Number,
  [Parameter(Mandatory)][string]$Owner,
  [ValidateSet('en','es')][string]$Lang = 'en',
  [string]$PresetPath
)
$ErrorActionPreference = 'Stop'
if (-not $PresetPath) { $PresetPath = Join-Path $PSScriptRoot "..\presets\fields.$Lang.json" }
if (-not (Test-Path $PresetPath)) { Write-Error "Preset not found: $PresetPath"; exit 1 }

# read as UTF-8 explicitly so accented names (ES preset: Área, revisión…) survive on Windows PowerShell 5.1
$preset   = Get-Content $PresetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$existing  = (gh project field-list $Number --owner $Owner --format json | ConvertFrom-Json).fields.name

foreach ($f in $preset.fields) {
  if ($existing -contains $f.name) { Write-Host "skip (exists): $($f.name)"; continue }
  if ($f.type -eq 'SINGLE_SELECT') {
    gh project field-create $Number --owner $Owner --name $f.name `
      --data-type SINGLE_SELECT --single-select-options ($f.options -join ',') | Out-Null
  } else {
    gh project field-create $Number --owner $Owner --name $f.name --data-type $f.type | Out-Null
  }
  Write-Host "created: $($f.name) ($($f.type))"
}
Write-Host "Preset '$Lang' applied to project #$Number (existing fields left untouched)."
