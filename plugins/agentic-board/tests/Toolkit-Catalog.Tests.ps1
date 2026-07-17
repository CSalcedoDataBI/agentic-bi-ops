#Requires -Modules Pester
<#  Pester tests for the toolkit catalogs (presets/toolkits/*.json) — schema + content. #>

BeforeAll {
    $script:ToolkitsDir = Join-Path $PSScriptRoot '..' 'presets' 'toolkits' | Resolve-Path
    $script:QualityPath = Join-Path $script:ToolkitsDir 'quality.json'
    $script:BiPath      = Join-Path $script:ToolkitsDir 'bi.json'

    $script:RequiredKeys = @('name','owner','repo','kind','path','license','homepage','profiles','install','purpose')

    function Get-Catalog([string]$Path) {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
}

Describe 'Toolkit catalogs' {
    It 'both catalog files exist' {
        Test-Path $script:QualityPath | Should -BeTrue
        Test-Path $script:BiPath      | Should -BeTrue
    }

    It 'both parse as valid JSON arrays' {
        { Get-Catalog $script:QualityPath } | Should -Not -Throw
        { Get-Catalog $script:BiPath }      | Should -Not -Throw
        @(Get-Catalog $script:QualityPath).Count | Should -BeGreaterThan 0
        @(Get-Catalog $script:BiPath).Count      | Should -BeGreaterThan 0
    }
}

Describe 'Entry schema' -ForEach @(
    @{ File = 'quality.json' }
    @{ File = 'bi.json' }
) {
    BeforeEach {
        $path = Join-Path $script:ToolkitsDir $File
        $script:entries = @(Get-Catalog $path)
    }

    It "<File>: every entry carries all required keys" {
        foreach ($e in $script:entries) {
            $names = $e.PSObject.Properties.Name
            foreach ($k in $script:RequiredKeys) {
                $names | Should -Contain $k -Because "entry '$($e.name)' in $File must define '$k'"
            }
        }
    }

    It "<File>: name/owner/repo/license/homepage/purpose are non-empty strings" {
        foreach ($e in $script:entries) {
            foreach ($k in 'name','owner','repo','license','homepage','purpose') {
                [string]::IsNullOrWhiteSpace([string]$e.$k) | Should -BeFalse -Because "$File/$($e.name).$k"
            }
        }
    }

    It "<File>: repo is 'owner/name'" {
        foreach ($e in $script:entries) { $e.repo | Should -Match '^[^/]+/[^/]+$' }
    }

    It "<File>: profiles is a non-empty array" {
        foreach ($e in $script:entries) { @($e.profiles).Count | Should -BeGreaterThan 0 }
    }

    It "<File>: kind is skill-clone or plugin, with matching path/install" {
        foreach ($e in $script:entries) {
            $e.kind | Should -BeIn @('skill-clone','plugin')
            if ($e.kind -eq 'plugin') {
                [string]::IsNullOrWhiteSpace([string]$e.install) | Should -BeFalse -Because "$($e.name) is a plugin — needs an install command"
                $e.path | Should -BeNullOrEmpty -Because "$($e.name) is a plugin — path must be null"
                [string]::IsNullOrWhiteSpace([string]$e.detect) | Should -BeFalse -Because "$($e.name) is a plugin — needs a detect id (marketplace/plugin) for gap detection"
            } else {
                [string]::IsNullOrWhiteSpace([string]$e.path) | Should -BeFalse -Because "$($e.name) is skill-clone — needs a path"
            }
        }
    }
}

Describe 'bi.json content' {
    BeforeEach { $script:bi = @(Get-Catalog $script:BiPath) }

    It 'includes microsoft/skills-for-fabric as an MIT plugin' {
        $ms = $script:bi | Where-Object { $_.repo -eq 'microsoft/skills-for-fabric' }
        $ms | Should -Not -BeNullOrEmpty
        $ms.kind    | Should -Be 'plugin'
        $ms.license | Should -Be 'MIT'
        $ms.owner   | Should -Be 'Microsoft'
    }

    It 'the Fabric entry covers the three BI profiles' {
        $ms = $script:bi | Where-Object { $_.repo -eq 'microsoft/skills-for-fabric' }
        foreach ($p in 'semantic-model-review','fabric-app','data-agent') {
            $ms.profiles | Should -Contain $p
        }
    }
}

Describe 'quality.json content' {
    It 'carries the four best-practice skills' {
        $names = @(Get-Catalog $script:QualityPath).name | Sort-Object
        $names | Should -Be (@('second-opinion','skill-creator','skill-improver','writing-skills'))
    }

    It 'every quality entry is skill-clone tagged with the quality profile' {
        foreach ($e in @(Get-Catalog $script:QualityPath)) {
            $e.kind     | Should -Be 'skill-clone'
            $e.profiles | Should -Contain 'quality'
        }
    }
}

Describe 'legacy catalog removed' {
    It 'presets/recommended-skills.json no longer exists (migrated to toolkits/)' {
        $legacy = Join-Path $PSScriptRoot '..' 'presets' 'recommended-skills.json'
        Test-Path $legacy | Should -BeFalse
    }
}
