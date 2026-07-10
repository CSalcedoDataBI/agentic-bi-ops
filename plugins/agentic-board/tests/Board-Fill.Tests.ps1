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
