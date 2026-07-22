#Requires -Modules Pester
<#  Tests for Board-Triage.ps1's pure triage logic (#306).

    Board-Triage.ps1 is side-effecting (reads/writes the board over gh), so it exposes a dot-source
    guard: with $env:ABIOS_TRIAGE_DOTSOURCE set it returns after defining the pure helpers. These
    tests pin the two rules the issue is about: the EVIDENCE fields (Type/Area/Estimate) are the ones
    flagged as gaps, and a Priority write is REFUSED without a rationale (the proposal must show its
    reasoning — never a silent P-value). #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Triage.ps1' | Resolve-Path
    $env:ABIOS_TRIAGE_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_TRIAGE_DOTSOURCE = ''
}

Describe 'Get-TriageGaps (evidence fields only)' {
    It 'flags every blank evidence field' {
        $g = Get-TriageGaps @{ Type = ''; Area = ''; Estimate = ''; Priority = '' }
        $g | Should -Contain 'Type'; $g | Should -Contain 'Area'; $g | Should -Contain 'Estimate'
    }
    It 'never flags Priority as a plain gap (it is filled only via the confirmed proposal)' {
        $g = Get-TriageGaps @{ Type = 'Bug'; Area = 'scripts'; Estimate = '3'; Priority = '' }
        $g | Should -BeNullOrEmpty
    }
    It 'reports only the still-blank evidence fields' {
        (Get-TriageGaps @{ Type = 'Bug'; Area = ''; Estimate = '2' }) | Should -Be @('Area')
    }
    It 'treats whitespace-only as blank' {
        (Get-TriageGaps @{ Type = '   '; Area = 'x'; Estimate = '1' }) | Should -Be @('Type')
    }
}

Describe 'Test-PriorityRequest (proposal must carry a rationale)' {
    It 'accepts no-Priority requests (nothing to validate)' {
        Test-PriorityRequest -Priority '' -Rationale '' | Should -BeNullOrEmpty
    }
    It 'refuses a Priority with no rationale (a silent P-value is exactly what #306 forbids)' {
        Test-PriorityRequest -Priority 'P1' -Rationale '' | Should -Match 'razonamiento'
    }
    It 'accepts a Priority that carries a rationale' {
        Test-PriorityRequest -Priority 'P1' -Rationale 'blocks the release' | Should -BeNullOrEmpty
    }
}

Describe 'Format-PriorityProposal (visible, correctable)' {
    It 'shows the issue, the P-value, and the reasoning on one line' {
        $line = Format-PriorityProposal -IssueNum 42 -Priority 'P1' -Rationale 'blocks the release'
        $line | Should -Match '#42'
        $line | Should -Match 'P1'
        $line | Should -Match 'blocks the release'
    }
}

Describe 'Get-TriageBoardPlan — never default to the tool board from a foreign repo (#382)' {
    It 'honors an explicit -Number as-is (no origin resolution)' {
        $p = Get-TriageBoardPlan -ExplicitNumber $true -ExplicitOwner $true -DefaultNumber 13 -DefaultOwner 'CSalcedoDataBI' -OriginRepo 'someone/other'
        $p.ResolveFromOrigin | Should -BeFalse
        $p.Number            | Should -Be 13
    }
    It 'resolves from origin when -Number is absent (the footgun fix)' {
        $p = Get-TriageBoardPlan -ExplicitNumber $false -ExplicitOwner $false -DefaultNumber 13 -DefaultOwner 'CSalcedoDataBI' -OriginRepo 'acme/reports'
        $p.ResolveFromOrigin | Should -BeTrue
        $p.Owner             | Should -Be 'acme'
        $p.Number            | Should -Be 0
    }
    It 'keeps an explicit -Owner even when resolving the board from origin' {
        $p = Get-TriageBoardPlan -ExplicitNumber $false -ExplicitOwner $true -DefaultNumber 13 -DefaultOwner 'MyOrg' -OriginRepo 'acme/reports'
        $p.ResolveFromOrigin | Should -BeTrue
        $p.Owner             | Should -Be 'MyOrg'
    }
    It 'refuses (no-origin) with neither an explicit -Number nor a usable origin — never falls back to #13' {
        $p = Get-TriageBoardPlan -ExplicitNumber $false -ExplicitOwner $false -DefaultNumber 13 -DefaultOwner 'CSalcedoDataBI' -OriginRepo ''
        $p.ResolveFromOrigin | Should -BeFalse
        $p.Reason            | Should -Be 'no-origin'
    }
}
