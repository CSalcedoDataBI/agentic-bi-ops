#Requires -Modules Pester
<#  Pester tests for Board-Fill.ps1 - the /board fill gap-filler.

    Board-Fill.ps1 is a side-effecting command (gh + Write-Host), so it exposes a
    dot-source guard: with $env:ABIOS_BOARDFILL_DOTSOURCE set, it returns after
    defining every function WITHOUT the token check or any gh call. That lets us
    unit-test the pure owner-resolution helpers, which encode the decision behind
    issue #86 (a board owner may be a USER or an ORGANIZATION). #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Fill.ps1' | Resolve-Path
    $env:ABIOS_BOARDFILL_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_BOARDFILL_DOTSOURCE = ''
}

Describe 'Get-OwnerRoot (owner-type -> GraphQL root, issue #86)' {
    It 'maps a User owner to the user() root' {
        Get-OwnerRoot -OwnerType 'User' | Should -Be 'user'
    }
    It 'maps an Organization owner to the organization() root' {
        Get-OwnerRoot -OwnerType 'Organization' | Should -Be 'organization'
    }
    It 'returns $null for an unknown / unresolved owner type' {
        Get-OwnerRoot -OwnerType $null   | Should -BeNullOrEmpty
        Get-OwnerRoot -OwnerType 'Bot'   | Should -BeNullOrEmpty
        Get-OwnerRoot -OwnerType ''      | Should -BeNullOrEmpty
    }
}

Describe 'Get-AllPages (board pagination - issue #246)' {
    It 'concatenates nodes across pages and stops when hasNext is false' {
        $script:calls = 0
        $fetch = {
            param($cursor)
            $script:calls++
            if ($script:calls -eq 1) { @{ nodes = @(1,2); hasNext = $true;  endCursor = 'c1' } }
            else                     { @{ nodes = @(3);   hasNext = $false; endCursor = $null } }
        }
        (Get-AllPages $fetch) | Should -Be @(1,2,3)
        $script:calls | Should -Be 2
    }
    It 'returns an empty array for a single empty page' {
        @(Get-AllPages { param($c) @{ nodes = @(); hasNext = $false; endCursor = $null } }).Count | Should -Be 0
    }
}

Describe 'Get-OwnerUrlSegment (projects URL segment)' {
    It 'uses /orgs/ for an organization' {
        Get-OwnerUrlSegment -OwnerType 'Organization' | Should -Be 'orgs'
    }
    It 'uses /users/ for a user' {
        Get-OwnerUrlSegment -OwnerType 'User' | Should -Be 'users'
    }
    It 'defaults to /users/ when the owner type is unknown' {
        Get-OwnerUrlSegment -OwnerType $null | Should -Be 'users'
        Get-OwnerUrlSegment -OwnerType ''    | Should -Be 'users'
    }
}

Describe 'Resolve-Opt (canonical option with legacy fallback, issue #278)' {
    BeforeAll {
        # Shaped like the GraphQL single-select field node Board-Fill resolves options from.
        $script:CanonStatus = [pscustomobject]@{ id = 'F1'; options = @(
            [pscustomobject]@{ id = 'c1'; name = 'Backlog' }
            [pscustomobject]@{ id = 'c2'; name = 'In Progress' }
        ) }
        $script:LegacyStatus = [pscustomobject]@{ id = 'F2'; options = @(
            [pscustomobject]@{ id = 'l1'; name = 'Todo' }
            [pscustomobject]@{ id = 'l2'; name = 'In Progress' }
        ) }
        $script:CanonPrio = [pscustomobject]@{ id = 'F3'; options = @(
            [pscustomobject]@{ id = 'p2'; name = 'P2' }
        ) }
        $script:LegacyPrio = [pscustomobject]@{ id = 'F4'; options = @(
            [pscustomobject]@{ id = 'q2'; name = 'P2 Medium' }
        ) }
    }
    It 'resolves the canonical name on a canonical board' {
        (Resolve-Opt $script:CanonStatus 'Status' 'Backlog').id | Should -Be 'c1'
    }
    It "resolves Backlog to a default-template board's 'Todo'" {
        $o = Resolve-Opt $script:LegacyStatus 'Status' 'Backlog'
        $o.id   | Should -Be 'l1'
        $o.name | Should -Be 'Todo'
    }
    It "fills Priority on the tool's OWN board - the P2/'P2 Medium' mismatch of #278" {
        (Resolve-Opt $script:CanonPrio  'Priority' 'P2').id | Should -Be 'p2'
        (Resolve-Opt $script:LegacyPrio 'Priority' 'P2').id | Should -Be 'q2'
    }
    It 'prefers the canonical name when a board carries both vocabularies' {
        $both = [pscustomobject]@{ options = @(
            [pscustomobject]@{ id = 'l1'; name = 'Todo' }
            [pscustomobject]@{ id = 'c1'; name = 'Backlog' }
        ) }
        (Resolve-Opt $both 'Status' 'Backlog').id | Should -Be 'c1'
    }
    It 'returns $null when the option is absent, so the caller skips that fill' {
        Resolve-Opt $script:CanonStatus 'Status' 'In Review' | Should -BeNullOrEmpty
    }
    It 'returns $null for a field the board does not have at all' {
        Resolve-Opt $null 'Size' 'M' | Should -BeNullOrEmpty
    }
}
