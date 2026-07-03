<#  Get-SkillGaps.ps1 — which recommended best-practice skills are missing?

    Reads the curated catalog (presets/recommended-skills.json), compares it against the
    skills actually installed (any scope, matched by name), and reports installed vs gaps.
    It NEVER installs anything and never duplicates — install is the agentic step the
    SKILL.md drives (git clone + copy + preserve license). Detection is deterministic.

    -InstalledNames overrides the detected install set (used by tests; defaults to the
    live inventory across all scopes).

    EXAMPLES
      .\Get-SkillGaps.ps1
      .\Get-SkillGaps.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot '..' 'presets' 'recommended-skills.json'),
    [string[]]$InstalledNames,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CatalogPath)) { throw "Catalog not found: $CatalogPath" }
$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json

if (-not $PSBoundParameters.ContainsKey('InstalledNames')) {
    $engine = Join-Path $PSScriptRoot 'Get-SkillInventory.ps1'
    $InstalledNames = (& $engine -Scope all).skills.name
}
$have = @{}
foreach ($n in $InstalledNames) { if ($n) { $have[$n.ToLower()] = $true } }

$installed = [System.Collections.Generic.List[object]]::new()
$gaps      = [System.Collections.Generic.List[object]]::new()
foreach ($c in $catalog) {
    if ($have.ContainsKey($c.name.ToLower())) { $installed.Add($c) } else { $gaps.Add($c) }
}

$result = [pscustomobject]@{
    summary   = [pscustomobject]@{ recommended = @($catalog).Count; installed = $installed.Count; gaps = $gaps.Count }
    installed = $installed
    gaps      = $gaps
}

if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
