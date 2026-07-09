<#  Install-SkillFromRepo.ps1 — clean-clone a single skill from a GitHub repo.

    Shallow-clones the source repo to a temp dir, copies ONLY the requested skill folder
    into the personal skills dir (~/.claude/skills/<name>), preserves the source LICENSE
    next to it (required for CC BY-SA and friends), and deletes the temp clone. Idempotent:
    refuses to overwrite an existing skill unless -Force.

    This is the install half of skills-bootstrap. Pair it with Get-SkillGaps.ps1 (which
    decides WHAT is missing) — never install something already present (no duplicates).

    EXAMPLE
      .\Install-SkillFromRepo.ps1 -Repo trailofbits/skills -Path skill-improver -Name skill-improver
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [string]$Dest,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if (-not $Dest) {
    $userHome = $env:USERPROFILE; if (-not $userHome) { $userHome = $HOME }
    $Dest = Join-Path $userHome '.claude/skills'
}
$target = Join-Path $Dest $Name
if ((Test-Path $target) -and -not $Force) {
    Write-Host "  SKIP  $Name already installed at $target (use -Force to overwrite)." -ForegroundColor DarkYellow
    return [pscustomobject]@{ name=$Name; installed=$false; reason='already-present'; path=$target }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("skillclone-" + [guid]::NewGuid().ToString('N'))
try {
    Write-Host "  Cloning $Repo (depth 1)..." -ForegroundColor Cyan
    git clone --depth 1 "https://github.com/$Repo.git" $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git clone failed for $Repo" }

    $src = Join-Path $tmp $Path
    if (-not (Test-Path $src)) { throw "Skill path '$Path' not found in $Repo." }

    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item (Join-Path $src '*') $target -Recurse -Force

    # Preserve attribution: copy the repo LICENSE if the skill folder lacks one.
    if (-not (Get-ChildItem $target -Filter 'LICENSE*' -ErrorAction SilentlyContinue)) {
        $lic = Get-ChildItem $tmp -Filter 'LICENSE*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lic) { Copy-Item $lic.FullName (Join-Path $target 'LICENSE') -Force }
    }
    Write-Host "  OK  installed $Name -> $target" -ForegroundColor Green
    [pscustomobject]@{ name=$Name; installed=$true; source="$Repo/$Path"; path=$target }
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
