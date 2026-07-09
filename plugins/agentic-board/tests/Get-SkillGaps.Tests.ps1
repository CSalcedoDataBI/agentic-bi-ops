#Requires -Modules Pester
<#  Pester tests for Get-SkillGaps.ps1 — gap detection against an injected install set. #>

BeforeAll {
    $script:Gaps = Join-Path $PSScriptRoot '..' 'scripts' 'Get-SkillGaps.ps1' | Resolve-Path
    $script:Catalog = Join-Path $PSScriptRoot '..' 'presets' 'recommended-skills.json' | Resolve-Path
}

Describe 'Get-SkillGaps' {
    It 'reports every recommended skill as a gap when none are installed' {
        $r = & $script:Gaps -InstalledNames @() -CatalogPath $script:Catalog
        $r.summary.installed | Should -Be 0
        $r.summary.gaps | Should -Be $r.summary.recommended
    }
    It 'detects an installed skill by name (case-insensitive) and never lists it as a gap' {
        $r = & $script:Gaps -InstalledNames @('Skill-Creator') -CatalogPath $script:Catalog
        $r.installed.name | Should -Contain 'skill-creator'
        $r.gaps.name | Should -Not -Contain 'skill-creator'
    }
    It 'counts installed + gaps to the full catalog (no double-count, no duplicates)' {
        $r = & $script:Gaps -InstalledNames @('writing-skills','second-opinion') -CatalogPath $script:Catalog
        ($r.summary.installed + $r.summary.gaps) | Should -Be $r.summary.recommended
        $r.summary.installed | Should -Be 2
    }
    It 'produces valid JSON' {
        $json = & $script:Gaps -InstalledNames @() -CatalogPath $script:Catalog -Json
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }
}
