<#  Add-KnowledgeRef.ps1 — add one reference to the project knowledge registry.
    Inits knowledge/registry.json (seeded taxonomy) if absent. Enforces the domain guard
    (declared or -NewDomain) and, for local refs, that the path exists (never invent
    references). Appends the record and regenerates KNOWLEDGE.md. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Ref,
    [Parameter(Mandatory)][string]$Domain,
    [string]$Title,
    [ValidateSet('repo','md','folder','url','notebooklm','video','')][string]$Type = '',
    [string]$Note = '',
    [switch]$NewDomain,
    [string]$Root = (Get-Location).Path,
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
$DefaultDomains = @('PowerBI','Fabric','DAX','TMDL','Power-Query','Vega','Claude-Code','Research')
function Test-IsUrl { param([string]$s) return ($s -match '^(https?)://') }

$dir = Join-Path $Root 'knowledge'
$regPath = Join-Path $dir 'registry.json'
if (Test-Path -LiteralPath $regPath) {
    $reg = Get-Content -LiteralPath $regPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $reg = [pscustomobject]@{ version=1; project=(Split-Path $Root -Leaf); domains=$DefaultDomains; references=@() }
}

if ($Domain -notin $reg.domains) {
    if (-not $NewDomain) { throw "Unknown domain '$Domain'. Use -NewDomain, or pick: $($reg.domains -join ', ')" }
    $reg.domains = @($reg.domains) + $Domain
}

$isUrl = Test-IsUrl $Ref
if (-not $isUrl -and -not (Test-Path -LiteralPath (Join-Path $Root $Ref))) {
    throw "Local ref does not exist: $Ref (never invent references)"
}

if ([string]::IsNullOrEmpty($Type)) {
    if ($isUrl) {
        if     ($Ref -match 'notebooklm\.google\.com')           { $Type = 'notebooklm' }
        elseif ($Ref -match '(youtube\.com|youtu\.be|vimeo\.com)') { $Type = 'video' }
        elseif ($Ref -match 'github\.com/[^/]+/[^/]+/?$')          { $Type = 'repo' }
        else                                                      { $Type = 'url' }
    } else {
        if     (Test-Path -LiteralPath (Join-Path $Root $Ref) -PathType Container) { $Type = 'folder' }
        else   { $Type = 'md' }
    }
}
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = if ($isUrl) { $Ref } else { Split-Path $Ref -Leaf } }

$max = 0
foreach ($r in @($reg.references)) { if ($r.id -match '^kn_(\d+)$' -and [int]$Matches[1] -gt $max) { $max = [int]$Matches[1] } }
$id = 'kn_{0:000}' -f ($max + 1)

$record = [pscustomobject]@{ id=$id; domain=$Domain; type=$Type; title=$Title; ref=$Ref; note=$Note; added=$Date }
$reg.references = @($reg.references) + $record

$reg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $regPath -Encoding utf8
& (Join-Path $PSScriptRoot 'Write-KnowledgeTable.ps1') -Root $Root | Out-Null

if ($Json) { $record | ConvertTo-Json -Depth 8 } else { $record }
