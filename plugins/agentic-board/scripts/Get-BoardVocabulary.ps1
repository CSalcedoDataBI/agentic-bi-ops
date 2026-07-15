<#  Get-BoardVocabulary.ps1 - the single source of truth for the board's option
    vocabulary: the CANONICAL option names (presets/fields.en.json) plus the
    LEGACY names that mean the same thing (GitHub's default Projects template,
    older hand-made boards).

    Why this exists (issue #278): the tool used to resolve options by one literal
    name per call site, and the call sites disagreed - Board-Work looked for
    'Backlog' (canonical) while Board-Fill looked for 'P2 Medium' (GitHub's
    template). No board could satisfy both. Every option lookup now goes through
    this map, so a board is understood whichever vocabulary it was born with, and
    Apply-FieldPreset -Migrate can rename the legacy names onto the canonical ones.

    Pure: dot-source it, it defines functions and data only (no gh, no output).
      . (Join-Path $PSScriptRoot 'Get-BoardVocabulary.ps1')

    All name comparisons are case-insensitive (PowerShell -eq / hashtable default).
#>

# Canonical option names per field, in preset order. Keep in sync with presets/fields.en.json.
$script:AbiosCanonicalOptions = @{
    Status   = @('Backlog', 'In Progress', 'In Review', 'Blocked', 'Done')
    Priority = @('P0', 'P1', 'P2', 'P3')
    Size     = @('XS', 'S', 'M', 'L', 'XL')
}

# Legacy names accepted as the same option. Key = canonical name, value = the
# aliases seen in the wild. Only add a name here when it unambiguously means the
# canonical one - an alias makes the tool ACT on the option (and -Migrate rename it).
$script:AbiosOptionAliases = @{
    Status   = @{
        'Backlog'   = @('Todo', 'To Do', 'To do', 'ToDo')
        'In Review' = @('Review', 'In review')
    }
    Priority = @{
        'P0' = @('P0 Critical', 'Critical')
        'P1' = @('P1 High', 'High')
        'P2' = @('P2 Medium', 'Medium')
        'P3' = @('P3 Low', 'Low')
    }
    Size     = @{}
}

# The canonical option names of a field ('Status', 'Priority', 'Size'), or an
# empty array for a field this tool has no opinion about (e.g. Type, or the ES
# preset's 'Estado' - a different field name, deliberately not migrated).
function Get-CanonicalOptionNames([string]$Field) {
    if ($Field -and $script:AbiosCanonicalOptions.ContainsKey($Field)) { @($script:AbiosCanonicalOptions[$Field]) } else { @() }
}

# $true only when $Name is EXACTLY a canonical option of $Field.
function Test-CanonicalOptionName([string]$Field, [string]$Name) {
    if (-not $Name) { return $false }
    (Get-CanonicalOptionNames $Field) -contains $Name
}

# Resolve any known name (canonical OR legacy alias) to its canonical name.
# Returns $null for a name this tool does not recognize - the caller must then
# treat the board's vocabulary as unknown rather than guess.
function Get-CanonicalOptionName([string]$Field, [string]$Name) {
    if (-not $Name) { return $null }
    if (Test-CanonicalOptionName $Field $Name) { return ((Get-CanonicalOptionNames $Field) | Where-Object { $_ -eq $Name } | Select-Object -First 1) }
    if (-not $script:AbiosOptionAliases.ContainsKey($Field)) { return $null }
    foreach ($canon in $script:AbiosOptionAliases[$Field].Keys) {
        if (@($script:AbiosOptionAliases[$Field][$canon]) -contains $Name) { return $canon }
    }
    return $null
}

# Every name that may carry a canonical option's value, canonical FIRST then its
# legacy aliases. Callers resolve an option id by walking this list in order, so a
# canonical board always wins over a legacy match.
function Get-OptionAliases([string]$Field, [string]$Canonical) {
    $names = @($Canonical)
    if ($script:AbiosOptionAliases.ContainsKey($Field) -and $script:AbiosOptionAliases[$Field].ContainsKey($Canonical)) {
        $names += @($script:AbiosOptionAliases[$Field][$Canonical])
    }
    @($names)
}

# The rename plan that puts a field's LEGACY options onto the canonical names.
# $Options = the field's existing options (objects with .id / .name).
#
# Renaming is done by option ID, so item assignments survive (see Apply-FieldPreset).
# An option is only planned when it is a known legacy alias; unknown names are left
# alone (never guess), and a rename whose target name ALREADY exists on the field is
# flagged Conflict - GitHub rejects duplicate option names, so the caller must report
# it instead of executing it.
function Get-LegacyOptionRenames {
    param([string]$Field, [object[]]$Options)
    $existing = @($Options | ForEach-Object { $_.name })
    foreach ($o in @($Options)) {
        $canon = Get-CanonicalOptionName $Field $o.name
        if (-not $canon)         { continue }   # unknown vocabulary - not ours to rename
        if ($canon -eq $o.name)  { continue }   # already canonical
        [pscustomobject]@{
            Id       = $o.id
            From     = $o.name
            To       = $canon
            Conflict = (@($existing | Where-Object { $_ -eq $canon }).Count -gt 0)
        }
    }
}
