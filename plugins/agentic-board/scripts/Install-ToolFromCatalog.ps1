<#  Install-ToolFromCatalog.ps1 — install referenced tools from the unified catalog (#387).

    Resolves items through Get-ToolsCatalog and installs by KIND, never duplicating:
      - skill-clone : delegates to Install-SkillFromRepo.ps1 (clean clone, LICENSE preserved).
      - plugin      : SURFACES its own install command (all-or-nothing) — never auto-run, because a
                      marketplace plugin is global/interactive and cherry-picking one skill is wrong.
      - reference   : a catalogued URL with no installer — reports it and the URL to open.
    An already-installed tool is skipped. -DryRun reports intent without touching anything.

    -Id           install ONE tool by id or name (case-insensitive).
    -DryRun       report what would happen; install nothing.
    -Root/-CatalogDir/-InstalledNames/-InstalledPlugins  passthrough to Get-ToolsCatalog.
    -Dest/-Force  passthrough to the skill installer.
    -InstallSkillWith  installer script path (default Install-SkillFromRepo.ps1) — injected in tests.

    EXAMPLES
      .\Install-ToolFromCatalog.ps1 -Id skill-creator
      .\Install-ToolFromCatalog.ps1 -Id skills-for-fabric   # prints the plugin's install command
#>
[CmdletBinding()]
param(
    [string]$Id,
    [switch]$DryRun,
    [string]$Root = (Get-Location).Path,
    [string]$CatalogDir,
    [string[]]$InstalledNames,
    [string[]]$InstalledPlugins,
    [string]$Dest,
    [switch]$Force,
    [string]$InstallSkillWith
)

$ErrorActionPreference = 'Stop'

if (-not $InstallSkillWith) { $InstallSkillWith = Join-Path $PSScriptRoot 'Install-SkillFromRepo.ps1' }
$resolver = Join-Path $PSScriptRoot 'Get-ToolsCatalog.ps1'

# forward only supplied resolver params
$fwd = @{ Root = $Root }
if ($CatalogDir) { $fwd.CatalogDir = $CatalogDir }
if ($PSBoundParameters.ContainsKey('InstalledNames'))   { $fwd.InstalledNames   = $InstalledNames }
if ($PSBoundParameters.ContainsKey('InstalledPlugins')) { $fwd.InstalledPlugins = $InstalledPlugins }

function Install-One($t) {
    if (-not $t.installable) {
        Write-Output ("  {0}: reference only (not installable). Open: {1}" -f $t.id, $t.url)
        return [pscustomobject]@{ id=$t.id; action='reference'; installed=$false }
    }
    if ($t.installed) {
        Write-Output ("  {0}: already installed - skipping." -f $t.id)
        return [pscustomobject]@{ id=$t.id; action='skip-installed'; installed=$true }
    }
    if ($t.kind -eq 'plugin') {
        Write-Output ("  {0}: plugin (all-or-nothing) - install it yourself:" -f $t.id)
        Write-Output ("      {0}" -f $t.installMethod)
        return [pscustomobject]@{ id=$t.id; action='surface-plugin'; installed=$false; command=$t.installMethod }
    }
    # skill-clone
    if ($DryRun) {
        Write-Output ("  {0}: WOULD clone {1}/{2} -> ~/.claude/skills/{3}" -f $t.id, $t.repo, $t.path, $t.name)
        return [pscustomobject]@{ id=$t.id; action='dry-run'; installed=$false }
    }
    $iargs = @{ Repo=$t.repo; Path=$t.path; Name=$t.name }
    if ($t.owner)   { $iargs.Owner   = $t.owner }
    if ($t.license) { $iargs.License = $t.license }
    if ($Dest)      { $iargs.Dest    = $Dest }
    if ($Force)     { $iargs.Force   = $true }
    $res = & $InstallSkillWith @iargs
    Write-Output ("  {0}: installed (skill-clone {1}/{2})." -f $t.id, $t.repo, $t.path)
    return [pscustomobject]@{ id=$t.id; action='install-skill'; installed=$true; result=$res }
}

if ($PSBoundParameters.ContainsKey('Id') -and $Id) {
    $item = @((& $resolver @fwd -Id $Id).items)
    if ($item.Count -eq 0) {
        Write-Output "Tool '$Id' not found in the catalog. Run /tools browse to see valid ids."
        return
    }
    return (Install-One $item[0])
}

Write-Output "Nothing to do: pass -Id <id> to install one tool (or -All once #388 lands)."
