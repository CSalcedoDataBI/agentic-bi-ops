#Requires -Modules Pester
<#  Tests for Resolve-Board.ps1 - the read must FAIL CLOSED (#313, part of #303).

    Resolve-Board's whole job is "find-or-reuse, create only if none exists". The find is a
    `gh project list` read, and a gh failure that read as an empty list would send the script
    straight to `gh project create` - manufacturing a duplicate of the board it just could not
    read. That is the #86 bug in one script. After #313 the read goes through Invoke-Gh, so a
    gh failure THROWS before the create.

    The seam here is the `gh` executable itself: mocking it (exit 1, empty stdout) reproduces
    the real 401 with no token and no network. A regression to bare `gh ... | ConvertFrom-Json`
    would NOT throw under this mock - it would proceed to create - so `Should -Throw` plus a
    `create -Times 0 -Exactly` is what pins the fix. (`-Times 0` alone is a vacuous pass; the
    `-Exactly` is the assertion.) #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Resolve-Board.ps1' | Resolve-Path
}

Describe 'Resolve-Board fails closed when the board-list read fails (#313)' {

    It 'THROWS instead of CREATING a duplicate board when gh exits non-zero' {
        Mock gh { $global:LASTEXITCODE = 1 }
        { & $script:Script -Owner 'X' -Repo 'X/y' } | Should -Throw
        # The whole point: the create must never run off a failed read.
        Should -Invoke gh -ParameterFilter { $args -contains 'create' } -Times 0 -Exactly
    }

    It 'reuses an existing board without creating when the read succeeds' {
        Mock gh { $global:LASTEXITCODE = 0; '{"projects":[{"number":7,"title":"Widget Board"}]}' }
        (& $script:Script -Owner 'X' -Repo 'X/widget' -Title 'Widget Board') | Should -Be 7
        Should -Invoke gh -ParameterFilter { $args -contains 'create' } -Times 0 -Exactly
    }
}
