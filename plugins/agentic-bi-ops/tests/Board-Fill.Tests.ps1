#Requires -Modules Pester
<#  Pester tests for Board-Fill.ps1 - the /board fill gap-filler.

    Board-Fill.ps1 is a side-effecting command (gh + Write-Host), so it exposes a
    dot-source guard: with $env:ABIOS_BOARDFILL_DOTSOURCE set, it returns after
    defining every function WITHOUT the token check or any gh call. That lets us
    unit-test the pure owner-resolution selector Select-ProjectV2Node, which is the
    decision point behind issue #86 (user-vs-org board resolution). #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Fill.ps1' | Resolve-Path
    $env:ABIOS_BOARDFILL_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_BOARDFILL_DOTSOURCE = ''

    function New-ProjNode { param([string]$Id = 'PVT_x') [pscustomobject]@{ id = $Id; fields = [pscustomobject]@{ nodes = @() } } }
}

Describe 'Select-ProjectV2Node (user-vs-org resolution, issue #86)' {
    It 'returns the user node when the board is user-owned' {
        $u = New-ProjNode 'PVT_user'
        (Select-ProjectV2Node -UserNode $u -OrgNode $null).id | Should -Be 'PVT_user'
    }
    It 'falls back to the organization node when user() resolves to null' {
        $o = New-ProjNode 'PVT_org'
        (Select-ProjectV2Node -UserNode $null -OrgNode $o).id | Should -Be 'PVT_org'
    }
    It 'returns $null when neither owner type resolves (fail-loud upstream)' {
        Select-ProjectV2Node -UserNode $null -OrgNode $null | Should -BeNullOrEmpty
    }
    It 'treats a node without an id as unresolved' {
        $noId = [pscustomobject]@{ id = $null }
        Select-ProjectV2Node -UserNode $noId -OrgNode $null | Should -BeNullOrEmpty
    }
    It 'prefers the user node deterministically when both are present' {
        $u = New-ProjNode 'PVT_user'; $o = New-ProjNode 'PVT_org'
        (Select-ProjectV2Node -UserNode $u -OrgNode $o).id | Should -Be 'PVT_user'
    }
}
