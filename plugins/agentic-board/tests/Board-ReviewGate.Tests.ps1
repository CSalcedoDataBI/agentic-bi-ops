#Requires -Modules Pester
<#  Tests for Board-ReviewGate.ps1's pure foreign-commit detection (#309).

    Board-ReviewGate.ps1 is side-effecting (reads the PR over gh, waits for CI/review), so it exposes
    a dot-source guard: with $env:ABIOS_REVIEWGATE_DOTSOURCE set it returns after defining the pure
    helper. Find-ForeignCommits is the defence-in-depth backstop for #294: a commit GitHub associates
    with a DIFFERENT PR is not this issue's work. It is warn-only — these tests pin the detection, and
    the known limitation (a commit with no PR of its own is invisible) is asserted, not papered over. #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-ReviewGate.ps1' | Resolve-Path
    $env:ABIOS_REVIEWGATE_DOTSOURCE = '1'
    . $script:Script -Repo 'owner/repo'    # -Repo is Mandatory; the guard returns before it is used
    $env:ABIOS_REVIEWGATE_DOTSOURCE = ''
}

Describe 'Find-ForeignCommits — warn on commits owned by another PR (#309)' {
    It 'returns nothing when every commit belongs only to this PR (no false positive)' {
        $c = @(
            [pscustomobject]@{ Sha = 'aaa'; Pulls = @(50) },
            [pscustomobject]@{ Sha = 'bbb'; Pulls = @(50) }
        )
        Find-ForeignCommits -SelfPr 50 -Commits $c | Should -BeNullOrEmpty
    }
    It 'flags a commit associated with a DIFFERENT PR' {
        $f = Find-ForeignCommits -SelfPr 50 -Commits @([pscustomobject]@{ Sha = 'ccc'; Pulls = @(99) })
        @($f).Count      | Should -Be 1
        $f[0].Sha        | Should -Be 'ccc'
        $f[0].OtherPrs   | Should -Contain 99
    }
    It 'ignores this PR in a mixed association but keeps the foreign one' {
        $f = Find-ForeignCommits -SelfPr 50 -Commits @([pscustomobject]@{ Sha = 'ddd'; Pulls = @(50, 77) })
        @($f).Count      | Should -Be 1
        $f[0].OtherPrs   | Should -Be @(77)
    }
    It 'treats a commit with no PR association as not-foreign (invisible to this signal, documented)' {
        Find-ForeignCommits -SelfPr 50 -Commits @([pscustomobject]@{ Sha = 'eee'; Pulls = @() }) |
            Should -BeNullOrEmpty
    }
    It 'handles an empty commit set' {
        Find-ForeignCommits -SelfPr 50 -Commits @() | Should -BeNullOrEmpty
    }
}
