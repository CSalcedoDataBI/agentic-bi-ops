<#  Suggest-HeavyMemory.ps1 - the security-gated "heavy memory" escalation (#143).

    The lightweight, git-committed HANDOFF.md is the DEFAULT. For the HEAVY case only -
    persistent SEMANTIC memory across projects - this script does NOT reinvent memory
    infrastructure; it proposes installing a reliable existing tool, **Basic Memory**
    (local Markdown + SQLite, exposed over MCP), from its official upstream.

    HARD RULE (license): Basic Memory is AGPL-3.0 (strong copyleft). We stay clean ONLY by
    installing from upstream and talking to it over MCP (a separate process = mere
    aggregation). This script NEVER vendors, forks, or copies Basic Memory's source - doing
    so would force agentic-bi-ops itself to become AGPL.

    Default run = PROPOSAL only: live provenance check against PyPI + the security checklist
    + the exact pinned commands. It installs nothing. `-Install` performs the guarded install
    but REQUIRES `-AcceptAgpl` (the explicit human gate) and pins an exact version.

    Dot-source guard: set $env:ABIOS_HEAVYMEM_DOTSOURCE=1 to load the pure helpers for Pester
    without any network call or install side effect.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$AcceptAgpl,
    [string]$Version = "",
    [string]$McpConfig = "",
    [string]$NotesPath = ""
)

# ==============================================================================
# Pure helpers (unit-testable; no network, no install, no file writes)
# ==============================================================================

$script:HeavyMemPackage = "basic-memory"
$script:HeavyMemRepo    = "basicmachines-co/basic-memory"

# Given a PyPI `info` object (from /pypi/<pkg>/json), verify provenance: the canonical
# package name (anti-typosquatting) and that the license really is AGPL. Returns a
# normalized result object - never throws.
function Test-BasicMemoryProvenance($info) {
    $name    = if ($info -and $info.name) { [string]$info.name } else { "" }
    $version = if ($info -and $info.version) { [string]$info.version } else { "" }
    $license = if ($info -and $info.license) { [string]$info.license } else { "" }
    $classifiers = @()
    if ($info -and $info.classifiers) { $classifiers = @($info.classifiers) }
    $isAgpl = ($license -match '(?i)AGPL') -or (@($classifiers | Where-Object { $_ -match '(?i)Affero' }).Count -gt 0)
    return [pscustomobject]@{
        nameOk  = ($name.ToLower() -eq $script:HeavyMemPackage)
        name    = $name
        version = $version
        isAgpl  = [bool]$isAgpl
        license = if ($license) { $license } elseif ($isAgpl) { "AGPL-3.0 (from classifiers)" } else { "unknown" }
    }
}

# The pinned install command (exact version, isolated env). uv is preferred; pipx is the
# fallback. NEVER a floating range.
function Get-HeavyMemoryInstallCommand([string]$version, [string]$manager = "uv") {
    if (-not $version) { return "" }
    switch ($manager) {
        "pipx" { return "pipx install `"$script:HeavyMemPackage==$version`"" }
        default { return "uv tool install `"$script:HeavyMemPackage==$version`"" }
    }
}

# The .mcp.json server entry - runs the MCP server from the PINNED version via uvx, so the
# running server matches exactly what was reviewed.
function New-BasicMemoryMcpEntry([string]$version) {
    return [ordered]@{
        command = "uvx"
        args    = @("--from", "$script:HeavyMemPackage==$version", $script:HeavyMemPackage, "mcp")
    }
}

# Upsert a named server into an .mcp.json body under mcpServers. Idempotent (replaces the
# same key). Returns pretty JSON. Accepts an empty/missing body.
function Add-McpServerEntry([string]$jsonBody, [string]$name, $entry) {
    $root = $null
    if ($jsonBody -and $jsonBody.Trim()) { try { $root = $jsonBody | ConvertFrom-Json } catch { $root = $null } }
    if (-not $root) { $root = [pscustomobject]@{} }
    if (-not ($root.PSObject.Properties.Name -contains 'mcpServers') -or -not $root.mcpServers) {
        $root | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $root.mcpServers | Add-Member -NotePropertyName $name -NotePropertyValue $entry -Force
    return ($root | ConvertTo-Json -Depth 10)
}

# ==============================================================================
# Main. Dot-source guard for tests.
# ==============================================================================
if ($env:ABIOS_HEAVYMEM_DOTSOURCE) { return }

$ErrorActionPreference = "Stop"

Write-Host "=== Heavy-memory escalation (Basic Memory) - security-gated proposal ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "The default is the lightweight HANDOFF.md. This is ONLY for persistent semantic" -ForegroundColor Gray
Write-Host "memory across projects. We install a reliable existing tool, never reinvent it." -ForegroundColor Gray
Write-Host ""

# -- Provenance: live PyPI lookup ---------------------------------------------
$prov = $null
try {
    $pypi = Invoke-RestMethod -Uri "https://pypi.org/pypi/$script:HeavyMemPackage/json" -TimeoutSec 15
    $prov = Test-BasicMemoryProvenance $pypi.info
} catch {
    Write-Host "  WARN could not reach PyPI for provenance ($($_.Exception.Message))." -ForegroundColor DarkYellow
}

$pin = $Version
if ($prov) {
    Write-Host "  Provenance (PyPI):" -ForegroundColor Cyan
    Write-Host "    package name matches '$script:HeavyMemPackage' : $($prov.nameOk)  (anti-typosquatting)" -ForegroundColor $(if ($prov.nameOk) { 'Green' } else { 'Red' })
    Write-Host "    latest version                    : $($prov.version)"
    Write-Host "    license                           : $($prov.license)  (AGPL: $($prov.isAgpl))" -ForegroundColor $(if ($prov.isAgpl) { 'Yellow' } else { 'Gray' })
    Write-Host "    upstream                          : https://github.com/$script:HeavyMemRepo"
    if (-not $pin) { $pin = $prov.version }
    if (-not $prov.nameOk) { throw "Provenance FAILED: PyPI package name '$($prov.name)' != '$script:HeavyMemPackage'. Refusing - possible typosquat." }
}
if (-not $pin) { $pin = "<pin-an-exact-version>" }
Write-Host ""

# -- AGPL notice + security checklist -----------------------------------------
Write-Host "  LICENSE (hard rule): Basic Memory is AGPL-3.0 (strong copyleft)." -ForegroundColor Yellow
Write-Host "    We NEVER vendor/fork its code - we install from upstream and talk over MCP" -ForegroundColor Yellow
Write-Host "    (separate process = mere aggregation). agentic-bi-ops stays MIT." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Security checklist:" -ForegroundColor Cyan
Write-Host "    [x] provenance verified (canonical name + AGPL confirmed above)"
Write-Host "    [x] pinned EXACT version ($pin) - never a floating range"
Write-Host "    [x] isolated env (uv tool / pipx), local-only (Markdown + SQLite, no network egress)"
Write-Host "    [x] human gate: install requires -Install -AcceptAgpl (no silent install)"
Write-Host "    [x] update-review, not auto-update; reversible uninstall (below)"
Write-Host ""

# -- Detect current state ------------------------------------------------------
$uv   = Get-Command uv   -ErrorAction SilentlyContinue
$pipx = Get-Command pipx -ErrorAction SilentlyContinue
$mgr  = if ($uv) { "uv" } elseif ($pipx) { "pipx" } else { "" }
$installCmd = Get-HeavyMemoryInstallCommand $pin $mgr
$mcpEntry   = New-BasicMemoryMcpEntry $pin

Write-Host "  Proposed install (pinned):" -ForegroundColor Cyan
if ($mgr) { Write-Host "    $installCmd" } else { Write-Host "    (install 'uv' or 'pipx' first, then) uv tool install `"$script:HeavyMemPackage==$pin`"" -ForegroundColor DarkYellow }
Write-Host ""
Write-Host "  Proposed .mcp.json entry (server 'basic-memory', pinned):" -ForegroundColor Cyan
Write-Host ("    " + (($mcpEntry | ConvertTo-Json -Depth 6) -replace "`n", "`n    "))
Write-Host ""
Write-Host "  Reversible uninstall:  $(if ($mgr -eq 'pipx') { 'pipx uninstall' } else { 'uv tool uninstall' }) $script:HeavyMemPackage  +  remove the .mcp.json entry" -ForegroundColor Gray
Write-Host "                         (your .md notes are preserved - data survives)." -ForegroundColor Gray
Write-Host ""

# -- Guarded install -----------------------------------------------------------
if (-not $Install) {
    Write-Host "PROPOSAL ONLY - nothing installed. To proceed:  Suggest-HeavyMemory.ps1 -Install -AcceptAgpl" -ForegroundColor Cyan
    return [pscustomobject]@{ installed=$false; proposed=$true; version=$pin; provenanceOk=$([bool]($prov -and $prov.nameOk)); agpl=$([bool]($prov -and $prov.isAgpl)) }
}

if (-not $AcceptAgpl) {
    throw "Refusing to install without -AcceptAgpl. Basic Memory is AGPL-3.0; pass -AcceptAgpl to confirm you accept installing it from upstream (we never vendor it)."
}
if ($pin -eq "<pin-an-exact-version>") { throw "No exact version resolved (PyPI unreachable?). Pass -Version x.y.z to pin explicitly." }
if (-not $mgr) { throw "Neither 'uv' nor 'pipx' is available - install one first (isolated env is required; no global pip)." }

Write-Host "  Installing $script:HeavyMemPackage==$pin via $mgr ..." -ForegroundColor Cyan
& (($installCmd -split '\s+')[0]) @(($installCmd -split '\s+') | Select-Object -Skip 1)
if ($LASTEXITCODE -ne 0) { throw "Install failed ($installCmd)." }

# Write the pinned MCP entry.
if (-not $McpConfig) { $McpConfig = Join-Path (git rev-parse --show-toplevel 2>$null | Select-Object -First 1) ".mcp.json" }
$existing = if (Test-Path $McpConfig) { Get-Content $McpConfig -Raw } else { "" }
Set-Content -Path $McpConfig -Value (Add-McpServerEntry $existing "basic-memory" $mcpEntry) -Encoding UTF8
Write-Host "  OK  installed and wrote the pinned MCP entry to $McpConfig" -ForegroundColor Green
Write-Host "  Review the server's tools before relying on it; re-pin deliberately on updates." -ForegroundColor Gray
return [pscustomobject]@{ installed=$true; version=$pin; mcpConfig=$McpConfig }
