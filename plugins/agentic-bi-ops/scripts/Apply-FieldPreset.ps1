<#  Apply-FieldPreset.ps1 — idempotently create the fields of a preset on a Projects
    board AND apply the preset's canonical single-select option colors.

    `gh project field-create` cannot set option colors (GitHub auto-assigns random
    ones) — so after ensuring a single-select field exists, this script reconciles
    its option colors via GraphQL, preserving existing option IDs (item assignments
    survive) and adding any missing options from the preset.

    Preset single-select options may be a plain string OR {name,color}. Colors are
    applied only for fields whose options carry a color (Status, Priority); plain
    string options (e.g. Type) are left with GitHub's default colors.

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
$existing = (gh project field-list $Number --owner $Owner --format json | ConvertFrom-Json).fields.name

function Get-OptName($o)  { if ($o -is [string]) { $o } else { $o.name } }
function Get-OptColor($o) { if ($o -is [string]) { $null } else { $o.color } }

# Reconcile a single-select field's option colors from the preset. Preserves
# existing option IDs (so item assignments survive) and appends missing options.
function Set-OptionColors($fieldName, $presetOptions) {
  $q = gh api graphql -f query='
query($owner:String!,$num:Int!,$field:String!){
  user(login:$owner){ projectV2(number:$num){
    field(name:$field){ ... on ProjectV2SingleSelectField { id options { id name color } } }
  }}
}' -F "owner=$Owner" -F "num=$Number" -f "field=$fieldName" | ConvertFrom-Json
  $field = $q.data.user.projectV2.field
  if (-not $field.id) { Write-Host "  (no pude leer '$fieldName' para colorear)"; return }

  $current = @($field.options)
  $desired = @()

  # Preset options first, in preset order — preserve id by name, apply preset color.
  foreach ($po in $presetOptions) {
    $name  = Get-OptName $po
    $color = Get-OptColor $po
    $match = $current | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $entry = @{ name = $name; color = ($(if ($color) { $color } elseif ($match) { $match.color } else { 'GRAY' })); description = '' }
    if ($match) { $entry.id = $match.id; if (-not $color) { $entry.color = $match.color } }
    $desired += $entry
  }
  # Any existing option NOT in the preset — keep it untouched (id + current color).
  foreach ($co in $current) {
    if (-not ($presetOptions | Where-Object { (Get-OptName $_) -eq $co.name })) {
      $desired += @{ id = $co.id; name = $co.name; color = $co.color; description = '' }
    }
  }

  $mutation = 'mutation($fieldId:ID!, $opts:[ProjectV2SingleSelectFieldOptionInput!]!){ updateProjectV2Field(input:{ fieldId:$fieldId, singleSelectOptions:$opts }){ projectV2Field { ... on ProjectV2SingleSelectField { id } } } }'
  $body = @{ query = $mutation; variables = @{ fieldId = $field.id; opts = $desired } } | ConvertTo-Json -Depth 10
  $resp = $body | gh api graphql --input - | ConvertFrom-Json
  if ($resp.errors) { Write-Host "  WARN no pude colorear '$fieldName': $($resp.errors[0].message)" -ForegroundColor DarkYellow }
  else { Write-Host "  colors: $fieldName -> $(( $desired | ForEach-Object { $_.name } ) -join ', ')" -ForegroundColor DarkCyan }
}

foreach ($f in $preset.fields) {
  if ($existing -contains $f.name) {
    Write-Host "skip (exists): $($f.name)"
  } else {
    if ($f.type -eq 'SINGLE_SELECT') {
      $optNames = @($f.options | ForEach-Object { Get-OptName $_ })
      gh project field-create $Number --owner $Owner --name $f.name `
        --data-type SINGLE_SELECT --single-select-options ($optNames -join ',') | Out-Null
    } else {
      gh project field-create $Number --owner $Owner --name $f.name --data-type $f.type | Out-Null
    }
    Write-Host "created: $($f.name) ($($f.type))"
  }

  # Apply canonical colors when the preset provides any (idempotent; also upgrades
  # boards whose fields were created before colors were part of the preset).
  if ($f.type -eq 'SINGLE_SELECT' -and (@($f.options | Where-Object { Get-OptColor $_ }).Count -gt 0)) {
    Set-OptionColors $f.name $f.options
  }
}
Write-Host "Preset '$Lang' applied to project #$Number (existing fields left untouched; canonical colors reconciled)."
