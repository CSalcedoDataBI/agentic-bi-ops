#Requires -Modules Pester
<#  Pester tests for Board-Work.ps1 - the /board work driver.

    Board-Work.ps1 is a side-effecting command (gh + Write-Host), so it exposes a
    dot-source guard: with $env:ABIOS_BOARDWORK_DOTSOURCE set, it returns after
    defining every function WITHOUT the token check or any gh call. That lets us
    unit-test the pure helpers, and - by mocking the three gh-touching helpers
    (Get-BoardItem, Get-IssueBlockers, Get-LastClaim) - the batch safety refusals
    and the dry-run plan of Invoke-IssueStart, all with zero network access. #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Work.ps1' | Resolve-Path
    $env:ABIOS_BOARDWORK_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_BOARDWORK_DOTSOURCE = ''

    # A dummy board context - only consumed AFTER the dry-run/refusal early returns,
    # so it never has to be real for these tests.
    $script:Ctx = [pscustomobject]@{
        projectId  = 'PROJ'
        statusNode = [pscustomobject]@{ id = 'FIELD' }
        inProgId   = 'OPT'
    }

    # Build a fake board item shaped exactly like Get-BoardItem's GraphQL result.
    function New-FakeItem {
        param(
            [string]  $Title     = 'Do a thing',
            [string]  $Repo      = 'owner/repo',
            [string]  $State     = 'OPEN',
            [string]  $Status    = 'Backlog',
            [string[]]$Assignees = @()
        )
        [pscustomobject]@{
            id          = 'ITEM'
            fieldValues = [pscustomobject]@{ nodes = @(
                [pscustomobject]@{ field = [pscustomobject]@{ name = 'Status' }; name = $Status }
            ) }
            content = [pscustomobject]@{
                __typename = 'Issue'; number = 1; title = $Title; state = $State; url = 'u'
                assignees  = [pscustomobject]@{ nodes = @($Assignees | ForEach-Object { [pscustomobject]@{ login = $_ } }) }
                repository = [pscustomobject]@{ nameWithOwner = $Repo }
            }
        }
    }
}

Describe 'Get-ParallelQueue (batch parsing)' {
    It 'de-duplicates while preserving the requested order' {
        (Get-ParallelQueue 5,5,7,5) | Should -Be @(5,7)
    }
    It 'keeps an already-unique list untouched and in order' {
        (Get-ParallelQueue 3,1,2) | Should -Be @(3,1,2)
    }
    It 'drops non-positive numbers' {
        (Get-ParallelQueue 0,-3,4,-1) | Should -Be @(4)
    }
    It 'returns an empty array when nothing is valid' {
        @(Get-ParallelQueue 0,-1).Count | Should -Be 0
    }
    It 'returns an empty array for an empty input' {
        @(Get-ParallelQueue @()).Count | Should -Be 0
    }
    It 'splits a single comma-joined string (the `pwsh -File` case: "129,130" not @(129,130))' {
        (Get-ParallelQueue '129,130') | Should -Be @(129,130)
    }
    It 'splits comma tokens and trims whitespace' {
        (Get-ParallelQueue '129, 130 ,131') | Should -Be @(129,130,131)
    }
    It 'drops non-numeric junk tokens' {
        (Get-ParallelQueue 'abc,12x,7') | Should -Be @(7)
    }
}

Describe 'Get-IssueSlugBranch (branch naming)' {
    It 'slugifies a plain title' {
        Get-IssueSlugBranch 12 'Fix the thing' | Should -Be 'issue-12-fix-the-thing'
    }
    It 'collapses punctuation and trims dashes' {
        Get-IssueSlugBranch 9 '-Parallel batch start (foo)!' | Should -Be 'issue-9-parallel-batch-start-foo'
    }
    It 'truncates a long slug to <=40 chars on a word boundary' {
        $b = Get-IssueSlugBranch 7 'this is a very long issue title that keeps on going well past the limit'
        $b | Should -BeLike 'issue-7-*'
        $slug = $b -replace '^issue-7-', ''
        $slug.Length | Should -BeLessOrEqual 40
        $slug | Should -Not -Match '-$'   # never end on a dangling dash
    }
}

Describe 'Get-SessionBriefing' {
    BeforeAll { $script:Brief = Get-SessionBriefing 42 'owner/repo' 'issue-42-x' 'C:\wt\path' }
    It 'is a single line (safe to pass on a command line)' {
        $script:Brief | Should -Not -Match "`n"
    }
    It 'names the issue, repo, branch and worktree' {
        $script:Brief | Should -Match '#42'
        $script:Brief | Should -Match 'owner/repo'
        $script:Brief | Should -Match 'issue-42-x'
    }
    It 'points at the PR + review-gate finish' {
        $script:Brief | Should -Match 'New-BoardPR\.ps1 -Issue 42'
        $script:Brief | Should -Match 'review gate'
    }
    It 'tells the session it is autonomous (do not stop to ask)' {
        $script:Brief | Should -Match 'AUTONOMOUSLY'
    }
    It 'finishes the merge through the ruleset-safe Board-Merge.ps1' {
        $script:Brief | Should -Match 'Board-Merge\.ps1'
    }
}

Describe 'Resolve-ClaudeAuthVar' {
    It 'honors an explicit -ClaudeAuthVar even when the OAuth token exists' {
        Resolve-ClaudeAuthVar $true 'ANTHROPIC_API_KEY' $true | Should -Be 'ANTHROPIC_API_KEY'
    }
    It 'auto-prefers the subscription OAuth token when not explicit and it is present' {
        Resolve-ClaudeAuthVar $false 'ANTHROPIC_API_KEY' $true | Should -Be 'CLAUDE_CODE_OAUTH_TOKEN'
    }
    It 'falls back to the default when not explicit and no OAuth token' {
        Resolve-ClaudeAuthVar $false 'ANTHROPIC_API_KEY' $false | Should -Be 'ANTHROPIC_API_KEY'
    }
}

Describe 'Build-WorktreeLaunch' {
    It 'builds a Windows Terminal tab command when wt is present' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launcher | Should -Be 'wt'
        $p.usesWt   | Should -BeTrue
        $p.args     | Should -Contain 'new-tab'
        $p.args     | Should -Contain '--startingDirectory'
        $p.args     | Should -Contain 'C:\wt'
    }
    It 'launches via a -File script, never an inline -Command (so wt cannot split the tab)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.args | Should -Contain '-File'
        $p.args | Should -Not -Contain '-Command'
        $p.args | Should -Contain $p.launchScriptFile
    }
    It 'REGRESSION: puts no semicolon on the wt command line (a ; there splits one tab into many)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        ($p.args -join ' ') | Should -Not -Match ';'
    }
    It 'names the launch script per issue, alongside the briefing' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\abios\brief.txt' 'C:\brief.txt'
        # launchScriptFile sits in the briefing's directory, keyed by issue number
        $p.launchScriptFile | Should -Match 'launch-12\.ps1$'
    }
    It 'falls back to a pwsh window when wt is absent' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launcher | Should -Be 'pwsh'
        $p.usesWt   | Should -BeFalse
        $p.args     | Should -Contain '-NoExit'
        $p.args     | Should -Contain '-File'
    }
    It 'passes the briefing by file, never inline' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launchScript | Should -Match 'brief\.txt'
    }
    It 'runs the spawned session unattended headless (no interactive prompt can stall it)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launchScript | Should -Match 'claude -p '                          # headless: skips trust + bypass-accept prompts
        $p.launchScript | Should -Match '--permission-mode bypassPermissions' # no per-tool approval stalls
        $p.launchScript | Should -Match '--no-session-persistence'            # parallel sessions don't collide
    }
    It 'injects the child auth credential by env-var NAME (secret never on the command line)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt' 'abios-parallel' 'MY_AUTH_VAR'
        # same-name injection: $env:MY_AUTH_VAR = [Environment]::GetEnvironmentVariable('MY_AUTH_VAR','User')
        $p.launchScript | Should -Match '\$env:MY_AUTH_VAR='                       # sets the child's credential
        $p.launchScript | Should -Match "GetEnvironmentVariable\('MY_AUTH_VAR','User'"  # read at runtime, by NAME, from registry
        $p.launchScript | Should -Match 'Remove-Item Env:CLAUDECODE'              # drop inherited host session markers
    }
    It 'defaults the auth credential to ANTHROPIC_API_KEY' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launchScript | Should -Match '\$env:ANTHROPIC_API_KEY='
    }
    It 'clears competing Anthropic credentials so the chosen one is authoritative' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        # with CLAUDE_CODE_OAUTH_TOKEN chosen, the inherited ANTHROPIC_API_KEY must be cleared
        # first (it outranks the OAuth token in auth precedence) or it would win silently.
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt' 'abios-parallel' 'CLAUDE_CODE_OAUTH_TOKEN'
        $s = $p.launchScript
        $s | Should -Match 'Remove-Item Env:ANTHROPIC_API_KEY,Env:ANTHROPIC_AUTH_TOKEN,Env:CLAUDE_CODE_OAUTH_TOKEN'
        # ...and the clear happens BEFORE the chosen credential is set
        $clearIdx = $s.IndexOf('Remove-Item Env:ANTHROPIC_API_KEY')
        $setIdx   = $s.IndexOf('$env:CLAUDE_CODE_OAUTH_TOKEN=')
        $clearIdx | Should -BeLessThan $setIdx
    }
    It 'rejects an auth-var name that could inject into the spawned command' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        { Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt' 'abios-parallel' "X'); rm -rf /; #" } | Should -Throw
    }
    It 'escapes single quotes in the briefing path (no literal break / injection)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' "C:\O'Brien\brief.txt"
        $p.launchScript | Should -Match "O''Brien"
    }
}

Describe 'Invoke-IssueStart safety refusals + dry-run' {
    BeforeEach {
        Mock Get-IssueBlockers { @() }          # not blocked unless a test overrides
        Mock Get-LastClaim     { '' }           # never hit the network for the claim
    }

    It 'skips a CLOSED issue without starting it' {
        Mock Get-BoardItem { New-FakeItem -State 'CLOSED' }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me'
        $r.started | Should -BeFalse
        $r.skipped | Should -Match 'CERRADO'
    }

    It 'skips an issue that is not on the board' {
        Mock Get-BoardItem { $null }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me'
        $r.started | Should -BeFalse
        $r.skipped | Should -Match 'no esta en el board'
    }

    It 'skips a blocked issue (and reports the blocker)' {
        Mock Get-BoardItem     { New-FakeItem }
        Mock Get-IssueBlockers { @("label 'blocked' presente") }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me'
        $r.started | Should -BeFalse
        $r.skipped | Should -Match 'BLOQUEADO'
        $r.skipped | Should -Match 'blocked'
    }

    It 'respects -IgnoreBlocked (a blocked issue is no longer skipped for that reason)' {
        Mock Get-BoardItem     { New-FakeItem }
        Mock Get-IssueBlockers { @("label 'blocked' presente") }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me' -IgnoreBlocked -DryRunStart
        $r.skipped | Should -Be ''
        $r.dryRun  | Should -BeTrue
    }

    It 'skips an issue already In Progress + assigned (multi-session lock)' {
        Mock Get-BoardItem { New-FakeItem -Status 'In Progress' -Assignees @('bob') }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me'
        $r.started | Should -BeFalse
        $r.skipped | Should -Match 'OCUPADO'
    }

    It '-TakeOver overrides the lock (reaches the plan instead of skipping)' {
        Mock Get-BoardItem { New-FakeItem -Status 'In Progress' -Assignees @('bob') }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me' -TakeOver -DryRunStart
        $r.skipped | Should -Be ''
        $r.dryRun  | Should -BeTrue
    }

    It 'plans (does not mutate) a clean issue under -DryRunStart' {
        Mock Get-BoardItem { New-FakeItem -Title 'Add a widget' }
        $r = Invoke-IssueStart -IssueNum 1 -Ctx $script:Ctx -Owner 'me' -DryRunStart
        $r.started | Should -BeFalse
        $r.dryRun  | Should -BeTrue
        $r.skipped | Should -Be ''
        $r.branch  | Should -Match '^issue-1-'
    }
}
