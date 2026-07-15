#Requires -Modules Pester
<#  Pester tests for Get-BoardVocabulary.ps1 - the canonical/legacy option map
    behind issue #278 (a board born from GitHub's default template used to be
    silently invisible to /board work, and /board field apply could not migrate it). #>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'Get-BoardVocabulary.ps1' | Resolve-Path)
}

Describe 'Get-CanonicalOptionNames' {
    It 'returns the canonical Status options in preset order' {
        Get-CanonicalOptionNames 'Status' | Should -Be @('Backlog', 'In Progress', 'In Review', 'Blocked', 'Done')
    }
    It 'returns an empty array for a field with no canonical vocabulary' {
        @(Get-CanonicalOptionNames 'Type').Count  | Should -Be 0
        @(Get-CanonicalOptionNames 'Estado').Count | Should -Be 0
        @(Get-CanonicalOptionNames $null).Count   | Should -Be 0
    }
}

Describe 'Get-CanonicalOptionName (legacy -> canonical)' {
    It "maps GitHub's default-template 'Todo' to 'Backlog'" {
        Get-CanonicalOptionName 'Status' 'Todo'  | Should -Be 'Backlog'
        Get-CanonicalOptionName 'Status' 'To Do' | Should -Be 'Backlog'
    }
    It 'maps the verbose Priority names onto P0..P3' {
        Get-CanonicalOptionName 'Priority' 'P2 Medium'   | Should -Be 'P2'
        Get-CanonicalOptionName 'Priority' 'P0 Critical' | Should -Be 'P0'
        Get-CanonicalOptionName 'Priority' 'Low'         | Should -Be 'P3'
    }
    It 'returns a canonical name unchanged' {
        Get-CanonicalOptionName 'Status'   'Backlog' | Should -Be 'Backlog'
        Get-CanonicalOptionName 'Priority' 'P2'      | Should -Be 'P2'
    }
    It 'is case-insensitive' {
        Get-CanonicalOptionName 'Status' 'todo'    | Should -Be 'Backlog'
        Get-CanonicalOptionName 'Status' 'BACKLOG' | Should -Be 'Backlog'
    }
    It 'returns $null for an unrecognized name instead of guessing' {
        Get-CanonicalOptionName 'Status' 'Pendiente'  | Should -BeNullOrEmpty
        Get-CanonicalOptionName 'Status' 'Icebox'     | Should -BeNullOrEmpty
        Get-CanonicalOptionName 'Status' ''           | Should -BeNullOrEmpty
        Get-CanonicalOptionName 'Status' $null        | Should -BeNullOrEmpty
    }
    It 'returns $null for a field outside the vocabulary' {
        Get-CanonicalOptionName 'Type' 'Bug' | Should -BeNullOrEmpty
    }
}

Describe 'Test-CanonicalOptionName' {
    It 'accepts only exact canonical names' {
        Test-CanonicalOptionName 'Status' 'Backlog' | Should -BeTrue
        Test-CanonicalOptionName 'Status' 'Todo'    | Should -BeFalse
        Test-CanonicalOptionName 'Status' $null     | Should -BeFalse
    }
}

Describe 'Get-OptionAliases (lookup order)' {
    It 'puts the canonical name first, then its legacy aliases' {
        Get-OptionAliases 'Priority' 'P2' | Should -Be @('P2', 'P2 Medium', 'Medium')
    }
    It 'returns just the canonical name when it has no aliases' {
        Get-OptionAliases 'Status' 'Done' | Should -Be @('Done')
    }
    It 'returns just the name for a field outside the vocabulary' {
        Get-OptionAliases 'Type' 'Bug' | Should -Be @('Bug')
    }
}

Describe 'Get-LegacyOptionRenames (the -Migrate plan)' {
    It "plans Todo -> Backlog on a default-template board, by option ID" {
        $opts = @(
            [pscustomobject]@{ id = 'o1'; name = 'Todo' }
            [pscustomobject]@{ id = 'o2'; name = 'In Progress' }
            [pscustomobject]@{ id = 'o3'; name = 'Done' }
        )
        $plan = @(Get-LegacyOptionRenames -Field 'Status' -Options $opts)
        $plan.Count      | Should -Be 1
        $plan[0].Id      | Should -Be 'o1'
        $plan[0].From    | Should -Be 'Todo'
        $plan[0].To      | Should -Be 'Backlog'
        $plan[0].Conflict | Should -BeFalse
    }
    It 'plans nothing for an already-canonical board (idempotent)' {
        $opts = @(
            [pscustomobject]@{ id = 'o1'; name = 'Backlog' }
            [pscustomobject]@{ id = 'o2'; name = 'Done' }
        )
        @(Get-LegacyOptionRenames -Field 'Status' -Options $opts).Count | Should -Be 0
    }
    It 'leaves an unknown option name alone instead of guessing' {
        $opts = @([pscustomobject]@{ id = 'o1'; name = 'Icebox' })
        @(Get-LegacyOptionRenames -Field 'Status' -Options $opts).Count | Should -Be 0
    }
    It 'flags a rename whose canonical target already exists (GitHub rejects duplicates)' {
        $opts = @(
            [pscustomobject]@{ id = 'o1'; name = 'Todo' }
            [pscustomobject]@{ id = 'o2'; name = 'Backlog' }
        )
        $plan = @(Get-LegacyOptionRenames -Field 'Status' -Options $opts)
        $plan.Count       | Should -Be 1
        $plan[0].Conflict | Should -BeTrue
    }
    It 'plans every legacy Priority option at once' {
        $opts = @(
            [pscustomobject]@{ id = 'p0'; name = 'P0 Critical' }
            [pscustomobject]@{ id = 'p1'; name = 'P1 High' }
            [pscustomobject]@{ id = 'p2'; name = 'P2 Medium' }
        )
        $plan = @(Get-LegacyOptionRenames -Field 'Priority' -Options $opts)
        @($plan | ForEach-Object { $_.To }) | Should -Be @('P0', 'P1', 'P2')
        @($plan | Where-Object { $_.Conflict }).Count | Should -Be 0
    }
    It 'plans nothing for an empty option set' {
        @(Get-LegacyOptionRenames -Field 'Status' -Options @()).Count | Should -Be 0
    }
}
