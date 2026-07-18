#Requires -Modules Pester
<#  Pester tests for the Command Surface Contract (CONTRIBUTING.md § "Command surface").

    Enforces the invariant that let a menu tell users to type `/abios-feedback` (a command that
    does not exist): the typed surface and the internal skills must never be confused.
      - Every typed command (commands/*.md) has a non-empty description.
      - No command file presents an internal (user-invocable:false) skill as a typeable `/x`.
      - Every menu-style entry line that begins with `/x` resolves to a real command.

    Pester 5 scoping: `-ForEach` cases are built at SCRIPT (discovery) scope; everything the It
    BODIES read (RealCommands, CommandFiles) is (re)built in BeforeAll (run scope).
#>

# --- discovery scope: -ForEach cases ------------------------------------------
$CommandCases = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'commands') -Filter '*.md' |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
)
$SkillCases = @(
    Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'skills') -Directory | ForEach-Object {
        $md = Join-Path $_.FullName 'SKILL.md'
        if ((Test-Path $md) -and ((Get-Content -LiteralPath $md -Raw) -match '(?m)^\s*user-invocable:\s*false\s*$')) {
            @{ Skill = $_.Name }
        }
    }
)

BeforeAll {
    $script:CommandsDir  = Join-Path $PSScriptRoot '..' 'commands'
    $script:CommandFiles = @(Get-ChildItem -Path $script:CommandsDir -Filter '*.md')
    $script:RealCommands = @($script:CommandFiles.BaseName)
    $script:InternalSkills = @(
        Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'skills') -Directory | ForEach-Object {
            $md = Join-Path $_.FullName 'SKILL.md'
            if ((Test-Path $md) -and ((Get-Content -LiteralPath $md -Raw) -match '(?m)^\s*user-invocable:\s*false\s*$')) { $_.Name }
        }
    )
}

Describe 'Command surface — commands' {
    It 'discovers at least one real command' {
        $script:RealCommands.Count | Should -BeGreaterThan 0
    }

    It '<Name> has a non-empty description in its frontmatter' -ForEach $CommandCases {
        $desc = ''
        $lines = Get-Content -LiteralPath $Path
        if ($lines[0] -eq '---') {
            for ($i = 1; $i -lt $lines.Count -and $lines[$i] -ne '---'; $i++) {
                if ($lines[$i] -match '^\s*description:\s*(.*)$') { $desc = $matches[1]; break }
            }
        }
        [string]::IsNullOrWhiteSpace($desc) | Should -BeFalse -Because "$Name feeds the palette and the generated README catalog"
    }
}

Describe 'Command surface — internal skills are never dressed as /x' {
    It 'discovers internal (user-invocable:false) skills including abios-feedback' {
        $script:InternalSkills.Count | Should -BeGreaterThan 0
        $script:InternalSkills | Should -Contain 'abios-feedback'
    }

    It 'no command file presents internal skill /<Skill> as typeable' -ForEach $SkillCases {
        $needle = "/$Skill"
        foreach ($cmd in $script:CommandFiles) {
            (Get-Content -LiteralPath $cmd.FullName -Raw) | Should -Not -BeLike "*$needle*" -Because "$($cmd.Name) must not offer $needle — it is an internal skill, invoked by the model, not typed"
        }
    }
}

Describe 'Command surface — menu entries resolve to real commands' {
    It '<Name>: every line starting with /<token> is a real command' -ForEach $CommandCases {
        foreach ($line in (Get-Content -LiteralPath $Path)) {
            if ($line -match '^\s*/([a-z][a-z0-9-]+)') {
                $script:RealCommands | Should -Contain $matches[1] -Because "a menu entry '/$($matches[1])' in $Name must map to commands/$($matches[1]).md"
            }
        }
    }
}
