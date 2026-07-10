#Requires -Modules Pester
<#  Pester tests for Fleet-Plan.ps1 - the advisory board-lead planner (P3-2). It reads
    pending board issues and emits an assignment map (issue -> CLI -> dependency wave)
    WITHOUT launching anything. Side-effecting at the edges (gh), so a dot-source guard
    ($env:ABIOS_FLEETPLAN_DOTSOURCE) exposes the pure planner core for unit tests. #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Fleet-Plan.ps1' | Resolve-Path
    $env:ABIOS_FLEETPLAN_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_FLEETPLAN_DOTSOURCE = ''

    function New-Iss {
        param([int]$Number, [string]$Title = 't', [string[]]$Labels = @(), [string]$Size = 'M', [string]$Type = 'Feature', [int[]]$BlockedBy = @())
        [pscustomobject]@{ number = $Number; title = $Title; labels = $Labels; size = $Size; type = $Type; blockedBy = $BlockedBy }
    }
    $all = @('claude','codex','gemini','copilot')
}

Describe 'Select-CliForIssue (capability routing with availability fallback)' {
    It 'routes security/architecture/large work to claude' {
        Select-CliForIssue (New-Iss 1 -Labels 'security') $all | Should -Be 'claude'
        Select-CliForIssue (New-Iss 2 -Size 'L')          $all | Should -Be 'claude'
    }
    It 'routes refactors to codex when available' {
        Select-CliForIssue (New-Iss 3 -Type 'Refactor') $all | Should -Be 'codex'
    }
    It 'falls back to claude when the preferred CLI is not available' {
        Select-CliForIssue (New-Iss 4 -Type 'Refactor') @('claude','gemini') | Should -Be 'claude'
    }
    It 'routes docs to gemini' {
        Select-CliForIssue (New-Iss 5 -Type 'Docs') @('gemini','claude') | Should -Be 'gemini'
    }
    It 'routes small chores to copilot' {
        Select-CliForIssue (New-Iss 6 -Type 'Chore' -Size 'S') @('copilot','claude') | Should -Be 'copilot'
    }
    It 'defaults a plain feature to claude' {
        Select-CliForIssue (New-Iss 7) $all | Should -Be 'claude'
    }
    It 'uses the first available CLI when nothing preferred (not even claude) is present' {
        Select-CliForIssue (New-Iss 8 -Type 'Docs') @('copilot') | Should -Be 'copilot'
    }
}

Describe 'Get-AssignmentWaves (dependency-aware layering)' {
    It 'puts fully-independent issues in a single wave' {
        $w = Get-AssignmentWaves @( (New-Iss 1), (New-Iss 2), (New-Iss 3) )
        $w.Count | Should -Be 1
        @($w[0]).Count | Should -Be 3
    }
    It 'sequences a blocker before its dependent' {
        $w = Get-AssignmentWaves @( (New-Iss 1), (New-Iss 2 -BlockedBy 1) )
        $w.Count | Should -Be 2
        $w[0][0].number | Should -Be 1
        $w[1][0].number | Should -Be 2
    }
    It 'builds one wave per link in a chain A->B->C' {
        $w = Get-AssignmentWaves @( (New-Iss 1), (New-Iss 2 -BlockedBy 1), (New-Iss 3 -BlockedBy 2) )
        $w.Count | Should -Be 3
    }
    It 'treats a blocker OUTSIDE the pending set as already satisfied' {
        $w = Get-AssignmentWaves @( (New-Iss 5 -BlockedBy 99) )   # 99 not in the set
        $w.Count | Should -Be 1
        $w[0][0].number | Should -Be 5
    }
    It 'does not hang on a dependency cycle (places the rest in a final wave)' {
        $w = Get-AssignmentWaves @( (New-Iss 1 -BlockedBy 2), (New-Iss 2 -BlockedBy 1) )
        @($w | ForEach-Object { $_ }).Count | Should -BeGreaterThan 0
        # both issues still appear somewhere
        (@($w | ForEach-Object { $_ }) | ForEach-Object { $_.number } | Sort-Object) | Should -Be @(1,2)
    }
}

Describe 'New-AssignmentPlan (waves x routing)' {
    It 'assigns every issue a wave and a CLI' {
        $plan = New-AssignmentPlan @( (New-Iss 1 -Type 'Refactor'), (New-Iss 2 -BlockedBy 1 -Labels 'security') ) @('claude','codex')
        ($plan | Where-Object { $_.issue -eq 1 }).wave | Should -Be 1
        ($plan | Where-Object { $_.issue -eq 1 }).cli  | Should -Be 'codex'
        ($plan | Where-Object { $_.issue -eq 2 }).wave | Should -Be 2
        ($plan | Where-Object { $_.issue -eq 2 }).cli  | Should -Be 'claude'
    }
    It 'defaults to a claude-only fleet when no CLIs are given' {
        $plan = New-AssignmentPlan @( (New-Iss 1) ) @()
        $plan[0].cli | Should -Be 'claude'
    }
    It 'produces one plan entry per issue' {
        (New-AssignmentPlan @( (New-Iss 1), (New-Iss 2), (New-Iss 3) ) @('claude')).Count | Should -Be 3
    }
}
