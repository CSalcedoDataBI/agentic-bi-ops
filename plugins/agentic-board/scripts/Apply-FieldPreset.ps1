<#  Apply-FieldPreset.ps1 — idempotently create the fields of a preset on a Projects
    board AND apply the preset's canonical single-select option colors.

    `gh project field-create` cannot set option colors (GitHub auto-assigns random
    ones) — so after ensuring a single-select field exists, this script reconciles
    its option colors via GraphQL, preserving existing option IDs (item assignments
    survive) and adding any missing options from the preset.

    Preset single-select options may be a plain string OR {name,color}. Colors are
    applied only for fields whose options carry a color (Status, Priority); plain
    string options (e.g. Type) are left with GitHub's default colors.

    -Migrate — standardize an EXISTING board onto the canonical preset (issue #278).
    Without it, options are matched by NAME only: a board born from GitHub's default
    template keeps its legacy `Todo` and merely gains a `Backlog` NEXT TO it, so every
    item stays on `Todo`, the migration never happens, and the board ends up with two
    options meaning the same thing. With -Migrate, a legacy option (see
    Get-BoardVocabulary.ps1) is RENAMED IN PLACE onto its canonical name: the mutation
    is sent with the option's EXISTING id and the canonical name, so every item already
    assigned to it keeps its assignment — no bulk item rewrite, no orphaned items.
    Renaming touches every item at once, so the rename plan is printed and confirmed
    first (-DryRun previews, -Yes skips the prompt for CI).

    Requires $env:GH_TOKEN already set (via the gh-account skill).
    Usage:
      $env:GH_TOKEN = <token>
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -Lang en
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -Migrate -DryRun
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -Migrate
      ./Apply-FieldPreset.ps1 -Number 13 -Owner CSalcedoDataBI -PresetPath custom.json  #>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$Number,
  [Parameter(Mandatory)][string]$Owner,
  [ValidateSet('en','es')][string]$Lang = 'en',
  [string]$PresetPath,
  # Rename legacy option names onto the canonical ones (in place, by option id).
  [switch]$Migrate,
  # Print the plan (creations + renames) and exit without mutating anything.
  [switch]$DryRun,
  # Skip the migration confirmation prompt (CI / already-approved).
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'

# The canonical/legacy option vocabulary — the map that says `Todo` MEANS `Backlog`.
. (Join-Path $PSScriptRoot 'Get-BoardVocabulary.ps1')

if (-not $PresetPath) { $PresetPath = Join-Path $PSScriptRoot "..\presets\fields.$Lang.json" }
if (-not (Test-Path $PresetPath)) { Write-Error "Preset not found: $PresetPath"; exit 1 }

# read as UTF-8 explicitly so accented names (ES preset: Área, revisión…) survive on Windows PowerShell 5.1
$preset   = Get-Content $PresetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$existing = (gh project field-list $Number --owner $Owner --format json | ConvertFrom-Json).fields.name

function Get-OptName($o)  { if ($o -is [string]) { $o } else { $o.name } }
function Get-OptColor($o) { if ($o -is [string]) { $null } else { $o.color } }

# Read a single-select field's live id + options. Cached: the migration plan and the
# reconcile pass both need it, and it cannot change in between (we hold the only writer).
$script:FieldCache = @{}
function Get-SingleSelectField($fieldName) {
  if ($script:FieldCache.ContainsKey($fieldName)) { return $script:FieldCache[$fieldName] }
  $q = gh api graphql -f query='
query($owner:String!,$num:Int!,$field:String!){
  user(login:$owner){ projectV2(number:$num){
    field(name:$field){ ... on ProjectV2SingleSelectField { id options { id name color } } }
  }}
}' -F "owner=$Owner" -F "num=$Number" -f "field=$fieldName" | ConvertFrom-Json
  $script:FieldCache[$fieldName] = $q.data.user.projectV2.field
  return $script:FieldCache[$fieldName]
}

# Reconcile a single-select field's option colors from the preset. Preserves
# existing option IDs (so item assignments survive) and appends missing options.
# With -Migrate, a preset option with no exact name match also adopts a LEGACY
# option's id (renaming it in place) instead of being added beside it.
function Set-OptionColors($fieldName, $presetOptions) {
  $field = Get-SingleSelectField $fieldName
  if (-not $field.id) { Write-Host "  (no pude leer '$fieldName' para colorear)"; return }

  $current = @($field.options)
  $desired = @()
  $usedIds = @()   # ids already claimed by a preset option — never emit one twice (GitHub rejects it)

  # Preset options first, in preset order — preserve id by name, apply preset color.
  foreach ($po in $presetOptions) {
    $name  = Get-OptName $po
    $color = Get-OptColor $po
    $match = $current | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $match -and $Migrate) {
      # No option carries the canonical name — adopt the legacy one that MEANS it
      # (Todo -> Backlog). Same id + new name = rename in place; assignments survive.
      $match = $current | Where-Object {
        ($usedIds -notcontains $_.id) -and ((Get-CanonicalOptionName $fieldName $_.name) -eq $name)
      } | Select-Object -First 1
      if ($match) { Write-Host "  rename: $fieldName '$($match.name)' -> '$name' (conserva las asignaciones)" -ForegroundColor Cyan }
    }
    $entry = @{ name = $name; color = ($(if ($color) { $color } elseif ($match) { $match.color } else { 'GRAY' })); description = '' }
    if ($match) { $entry.id = $match.id; $usedIds += $match.id; if (-not $color) { $entry.color = $match.color } }
    $desired += $entry
  }
  # Any existing option NOT claimed above — keep it untouched (id + current color).
  foreach ($co in $current) {
    if ($usedIds -notcontains $co.id -and -not ($presetOptions | Where-Object { (Get-OptName $_) -eq $co.name })) {
      $desired += @{ id = $co.id; name = $co.name; color = $co.color; description = '' }
    }
  }

  $mutation = 'mutation($fieldId:ID!, $opts:[ProjectV2SingleSelectFieldOptionInput!]!){ updateProjectV2Field(input:{ fieldId:$fieldId, singleSelectOptions:$opts }){ projectV2Field { ... on ProjectV2SingleSelectField { id } } } }'
  $body = @{ query = $mutation; variables = @{ fieldId = $field.id; opts = $desired } } | ConvertTo-Json -Depth 10
  $resp = $body | gh api graphql --input - | ConvertFrom-Json
  if ($resp.errors) { Write-Host "  WARN no pude colorear '$fieldName': $($resp.errors[0].message)" -ForegroundColor DarkYellow }
  else { Write-Host "  colors: $fieldName -> $(( $desired | ForEach-Object { $_.name } ) -join ', ')" -ForegroundColor DarkCyan }
}

# ── Plan ──────────────────────────────────────────────────────────────────────
# Show what would change BEFORE touching anything: field creations, plus (with
# -Migrate) the in-place renames. Renames hit every item assigned to the option at
# once, so they are never executed without the user seeing this list.
$toCreate = @($preset.fields | Where-Object { $existing -notcontains $_.name })
$renames  = @()
if ($Migrate) {
  foreach ($f in ($preset.fields | Where-Object { $_.type -eq 'SINGLE_SELECT' -and $existing -contains $_.name })) {
    $live = Get-SingleSelectField $f.name
    if (-not $live.id) { continue }
    $renames += @(Get-LegacyOptionRenames -Field $f.name -Options @($live.options) |
                  ForEach-Object { $_ | Add-Member -NotePropertyName Field -NotePropertyValue $f.name -PassThru })
  }
}

if ($DryRun -or ($Migrate -and $renames.Count -gt 0)) {
  Write-Host "=== Plan: preset '$Lang' sobre el board #$Number de $Owner ===" -ForegroundColor Cyan
  if ($toCreate.Count -gt 0) {
    Write-Host "  Campos a crear: $(($toCreate | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor DarkCyan
  } else {
    Write-Host "  Campos a crear: ninguno (todos existen)" -ForegroundColor DarkGray
  }
  if ($Migrate) {
    $doable = @($renames | Where-Object { -not $_.Conflict })
    $stuck  = @($renames | Where-Object { $_.Conflict })
    if ($doable.Count -eq 0 -and $stuck.Count -eq 0) {
      Write-Host "  Renombres: ninguno (el board ya usa el vocabulario canonico)" -ForegroundColor DarkGray
    }
    foreach ($r in $doable) {
      Write-Host ("  rename: {0} '{1}' -> '{2}'  (los items asignados se conservan)" -f $r.Field, $r.From, $r.To) -ForegroundColor Yellow
    }
    foreach ($r in $stuck) {
      Write-Host ("  SKIP:   {0} '{1}' -> '{2}' — '{2}' ya existe en el campo; GitHub no admite dos opciones con el mismo nombre." -f $r.Field, $r.From, $r.To) -ForegroundColor DarkYellow
      Write-Host ("          Mueve los items de '{0}' a '{1}' y borra '{0}' a mano en la UI." -f $r.From, $r.To) -ForegroundColor DarkGray
    }
  }
  Write-Host ""
}

if ($DryRun) {
  Write-Host "DRY-RUN: no se ejecuto ningun cambio." -ForegroundColor Cyan
  Write-Host "Board: https://github.com/users/$Owner/projects/$Number" -ForegroundColor Cyan
  exit 0
}

if ($Migrate -and @($renames | Where-Object { -not $_.Conflict }).Count -gt 0 -and -not $Yes) {
  $answer = Read-Host "Aplicar estos renombres al board #$Number? (s/n)"
  if ($answer -notmatch '^(s|si|sí|y|yes)$') {
    Write-Host "Cancelado - no se cambio nada." -ForegroundColor Yellow
    Write-Host "Board: https://github.com/users/$Owner/projects/$Number" -ForegroundColor Cyan
    exit 0
  }
}

# ── Apply ─────────────────────────────────────────────────────────────────────
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
    $script:FieldCache.Remove($f.name) | Out-Null   # it exists now — re-read its live options
    Write-Host "created: $($f.name) ($($f.type))"
  }

  # Apply canonical colors when the preset provides any (idempotent; also upgrades
  # boards whose fields were created before colors were part of the preset), and
  # perform the -Migrate renames planned above.
  if ($f.type -eq 'SINGLE_SELECT' -and (@($f.options | Where-Object { Get-OptColor $_ }).Count -gt 0)) {
    Set-OptionColors $f.name $f.options
  }
}
$how = if ($Migrate) { "canonical colors reconciled; legacy option names migrated in place" }
       else          { "existing fields left untouched; canonical colors reconciled" }
Write-Host "Preset '$Lang' applied to project #$Number ($how)."
if (-not $Migrate) {
  Write-Host "(Si el board venia de la plantilla por defecto de GitHub, corre con -Migrate para renombrar 'Todo' -> 'Backlog' y estandarizarlo.)" -ForegroundColor DarkGray
}
Write-Host "Board: https://github.com/users/$Owner/projects/$Number" -ForegroundColor Cyan
