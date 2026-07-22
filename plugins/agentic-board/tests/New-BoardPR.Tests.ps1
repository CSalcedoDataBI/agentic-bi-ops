#Requires -Modules Pester
<#  Tests for New-BoardPR.ps1's pure PR-existence check (#336).

    New-BoardPR.ps1 is side-effecting (git push + gh pr create), so it exposes a dot-source guard:
    with $env:ABIOS_NEWBOARDPR_DOTSOURCE set it returns after defining the pure helper. The bug was
    `@($existing).Count -gt 0`: a phantom read row with a null `.number` counted as "PR exists", so
    `gh pr create` was skipped and the run reported success with a BLANK PR number. Get-ExistingPr
    treats a PR as existing only when the row carries a positive-integer number. #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'New-BoardPR.ps1' | Resolve-Path
    $env:ABIOS_NEWBOARDPR_DOTSOURCE = '1'
    . $script:Script -Issue 1              # -Issue is Mandatory; the guard returns before it is used
    $env:ABIOS_NEWBOARDPR_DOTSOURCE = ''
}

Describe 'Get-ExistingPr — a phantom row is not an existing PR (#336)' {
    It 'returns nothing for an empty read ([] -> create path)' {
        Get-ExistingPr @() | Should -BeNullOrEmpty
    }
    It 'returns nothing for a null read' {
        Get-ExistingPr $null | Should -BeNullOrEmpty
    }
    It 'ignores a phantom row with a null number (the bug: it skipped create and printed a blank PR)' {
        Get-ExistingPr @([pscustomobject]@{ number = $null; url = '' }) | Should -BeNullOrEmpty
    }
    It 'ignores a row whose number is zero' {
        Get-ExistingPr @([pscustomobject]@{ number = 0; url = 'x' }) | Should -BeNullOrEmpty
    }
    It 'returns the first genuine PR row (positive number -> iterate path)' {
        $r = Get-ExistingPr @([pscustomobject]@{ number = 42; url = 'https://x/42' })
        $r.number | Should -Be 42
    }
    It 'skips a leading phantom and returns the real PR behind it' {
        $r = Get-ExistingPr @(
            [pscustomobject]@{ number = $null; url = '' },
            [pscustomobject]@{ number = 7;     url = 'https://x/7' }
        )
        $r.number | Should -Be 7
    }
}
