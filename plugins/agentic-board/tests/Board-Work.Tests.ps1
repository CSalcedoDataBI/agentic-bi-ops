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

Describe 'Get-IssueWorktreePath (grouped worktree layout)' {
    It 'groups worktrees under <repo>--worktrees/issue-<n> (not scattered siblings)' {
        Get-IssueWorktreePath 'owner/agentic-board' 129 'C:\Repos' |
            Should -Be 'C:\Repos\agentic-board--worktrees\issue-129'
    }
    It 'uses only the repo name, dropping the owner' {
        Get-IssueWorktreePath 'CSalcedoDataBI/my-repo' 7 'D:\work' |
            Should -Be 'D:\work\my-repo--worktrees\issue-7'
    }
    It 'places every issue in the SAME grouping folder' {
        $a = Get-IssueWorktreePath 'o/r' 1 'C:\p'
        $b = Get-IssueWorktreePath 'o/r' 2 'C:\p'
        (Split-Path $a -Parent) | Should -Be (Split-Path $b -Parent)
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

Describe 'Get-SessionBriefing adapter-aware' {
    It 'keeps the claude briefing unchanged' {
        (Get-SessionBriefing 5 'o/r' 'issue-5-x' 'C:\wt' -Cli 'claude') | Should -Match 'AUTONOMOUSLY'
        (Get-SessionBriefing 5 'o/r' 'issue-5-x' 'C:\wt' -Cli 'claude') | Should -Match 'issue #5'
    }
    It 'still references the same PR + review-gate steps for any repl CLI' {
        (Get-SessionBriefing 5 'o/r' 'issue-5-x' 'C:\wt' -Cli 'gemini') | Should -Match 'New-BoardPR.ps1'
    }
    It 'defaults to claude behavior when -Cli is omitted' {
        (Get-SessionBriefing 5 'o/r' 'issue-5-x' 'C:\wt') | Should -Match 'AUTONOMOUSLY'
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

Describe 'Build-WorktreeLaunch adapter parity' {
    # GOLDEN fixture captured from the pre-refactor Build-WorktreeLaunch for a claude
    # launch of issue 42 (brief C:\b\briefing-42.txt). The adapter-driven refactor MUST
    # keep the claude launchScript + args byte-identical to these constants.
    BeforeAll {
        $script:GoldenLaunchScript = @(
            "Remove-Item Env:ANTHROPIC_API_KEY,Env:ANTHROPIC_AUTH_TOKEN,Env:CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue"
            "`$env:ANTHROPIC_API_KEY=[Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY','User')"
            "Remove-Item Env:CLAUDECODE,Env:CLAUDE_CODE_SESSION_ID,Env:CLAUDE_CODE_CHILD_SESSION,Env:CLAUDE_CODE_ENTRYPOINT -ErrorAction SilentlyContinue"
            "claude -p (Get-Content -Raw -LiteralPath 'C:\b\briefing-42.txt') --permission-mode bypassPermissions --no-session-persistence --verbose"
        ) -join "`r`n"
        $script:GoldenWtArgs = @('-w', 'abios-parallel', 'new-tab', '--title', 'issue-42',
                                 '--startingDirectory', 'C:\wt\issue-42', 'pwsh', '-NoExit', '-File', 'C:\b\launch-42.ps1')
    }

    It 'exposes a -Cli parameter (adapter selector) defaulting to claude' {
        $cmd = Get-Command Build-WorktreeLaunch
        $cmd.Parameters.ContainsKey('Cli') | Should -BeTrue
        # the added selector must be appended, keeping the 5 original positionals in order
        $cmd.Parameters['Cli'].ParameterType | Should -Be ([string])
    }
    It 'produces a launchScript byte-identical to the golden when -Cli claude is explicit' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 42 'C:\wt\issue-42' 'C:\b\briefing-42.txt' 'abios-parallel' 'ANTHROPIC_API_KEY' 'claude'
        $p.launchScript | Should -BeExactly $script:GoldenLaunchScript
    }
    It 'produces a launchScript byte-identical to the golden when -Cli is omitted (default claude)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 42 'C:\wt\issue-42' 'C:\b\briefing-42.txt' 'abios-parallel' 'ANTHROPIC_API_KEY'
        $p.launchScript | Should -BeExactly $script:GoldenLaunchScript
    }
    It 'produces args byte-identical to the golden wt args (explicit claude)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 42 'C:\wt\issue-42' 'C:\b\briefing-42.txt' 'abios-parallel' 'ANTHROPIC_API_KEY' 'claude'
        $p.args.Count            | Should -Be $script:GoldenWtArgs.Count
        ($p.args -join "`n")     | Should -BeExactly ($script:GoldenWtArgs -join "`n")
    }
    It 'produces args byte-identical to the golden wt args (default claude)' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { [pscustomobject]@{ Name = 'wt' } }
        $p = Build-WorktreeLaunch 42 'C:\wt\issue-42' 'C:\b\briefing-42.txt' 'abios-parallel' 'ANTHROPIC_API_KEY'
        $p.args.Count            | Should -Be $script:GoldenWtArgs.Count
        ($p.args -join "`n")     | Should -BeExactly ($script:GoldenWtArgs -join "`n")
    }
    It 'default (no -Cli) still yields a claude -p launch script' {
        Mock Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $p = Build-WorktreeLaunch 12 'C:\wt' 'C:\brief.txt'
        $p.launchScript | Should -Match 'claude -p '
    }
}

Describe 'Get-BranchDriftWarning (foreign-checkout guard)' {
    BeforeAll {
        # Build a session-registry entry shaped like Write-SessionRegistryEntry writes.
        function New-Session {
            param([int]$Issue, [string]$Branch, [string]$WorkPath, [int]$SessPid, [string]$Started = '2026-07-07 10:00')
            [pscustomobject]@{ issue = $Issue; repo = 'o/r'; branch = $Branch; workPath = $WorkPath; sessionPid = $SessPid; started = $Started }
        }
    }

    It 'returns null when the registry has no session for this PID' {
        Get-BranchDriftWarning -Sessions @() -SessionPid 100 -CurrentBranch 'issue-1-x' -CurrentPath 'C:\repo' | Should -BeNullOrEmpty
    }
    It 'returns null on a detached HEAD (no current branch to compare)' {
        $s = @(New-Session 1 'issue-1-x' 'C:\repo' 100)
        Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch '' -CurrentPath 'C:\repo' | Should -BeNullOrEmpty
    }
    It 'returns null when HEAD still matches the branch the session started here' {
        $s = @(New-Session 1 'issue-1-x' 'C:\repo' 100)
        Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'issue-1-x' -CurrentPath 'C:\repo' | Should -BeNullOrEmpty
    }
    It 'WARNS when HEAD drifted away from the started branch (the foreign-hook case)' {
        $s = @(New-Session 163 'issue-163-guard' 'C:\repo' 100)
        $w = Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'issue-180-other' -CurrentPath 'C:\repo'
        $w | Should -Match '#163'
        $w | Should -Match 'issue-163-guard'          # names the branch to return to
        $w | Should -Match 'git checkout issue-163-guard'
    }
    It 'ignores entries belonging to a different session PID' {
        $s = @(New-Session 1 'issue-1-x' 'C:\repo' 999)
        Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'main' -CurrentPath 'C:\repo' | Should -BeNullOrEmpty
    }
    It 'ignores a session started in a DIFFERENT working copy (a worktree elsewhere)' {
        $s = @(New-Session 1 'issue-1-x' 'C:\repo--worktrees\issue-1' 100)
        Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'main' -CurrentPath 'C:\repo' | Should -BeNullOrEmpty
    }
    It 'picks the most-recently-started in-place issue when several share the working copy' {
        $s = @(
            New-Session 1 'issue-1-old' 'C:\repo' 100 '2026-07-07 09:00'
            New-Session 2 'issue-2-new' 'C:\repo' 100 '2026-07-07 11:00'
        )
        $w = Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'main' -CurrentPath 'C:\repo'
        $w | Should -Match '#2'
        $w | Should -Not -Match '#1'
    }
    It 'matches the working path tolerant of trailing slash and case' {
        $s = @(New-Session 1 'issue-1-x' 'C:\Repo\' 100)
        Get-BranchDriftWarning -Sessions $s -SessionPid 100 -CurrentBranch 'issue-1-x' -CurrentPath 'c:\repo' | Should -BeNullOrEmpty
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

Describe 'Get-CliAdapters' {
    It "returns claude as the default adapter with all required fields" {
        $adapters = Get-CliAdapters
        $claude = $adapters | Where-Object { $_.Name -eq 'claude' }
        $claude              | Should -Not -BeNullOrEmpty
        $claude.Command      | Should -Be 'claude'
        $claude.Kind         | Should -Be 'repl'
        $claude.IsDefault    | Should -BeTrue
        $claude.BuildLaunch  | Should -BeOfType ([scriptblock])
        $claude.Probe        | Should -BeOfType ([scriptblock])
    }
    It "includes all five CLIs by name" {
        (Get-CliAdapters).Name | Should -Contain 'gemini'
        (Get-CliAdapters).Name | Should -Contain 'jules'
        (Get-CliAdapters).Name | Should -Contain 'codex'
        (Get-CliAdapters).Name | Should -Contain 'copilot'
    }
    It "marks exactly one adapter as default" {
        @(Get-CliAdapters | Where-Object { $_.IsDefault }).Count | Should -Be 1
    }
}

Describe 'Get-CliProbeStatus' {
    It 'returns ok on exit 0' {
        Get-CliProbeStatus -ExitCode 0 -Stderr "" | Should -Be 'ok'
    }
    It 'returns no-quota on a rate-limit/quota message' {
        Get-CliProbeStatus -ExitCode 1 -Stderr "Error: 429 rate limit exceeded" | Should -Be 'no-quota'
        Get-CliProbeStatus -ExitCode 1 -Stderr "quota exceeded for this project" | Should -Be 'no-quota'
    }
    It 'returns auth on a 401/authentication message' {
        Get-CliProbeStatus -ExitCode 1 -Stderr "401 Unauthorized: please login" | Should -Be 'auth'
    }
    It 'returns error on any other non-zero exit' {
        Get-CliProbeStatus -ExitCode 1 -Stderr "some unexpected failure" | Should -Be 'error'
    }
    It 'catches quota error even on exit 0' {
        Get-CliProbeStatus -ExitCode 0 -Stderr "quota exceeded" | Should -Be 'no-quota'
    }
    It 'catches auth error even on exit 0' {
        Get-CliProbeStatus -ExitCode 0 -Stderr "not logged in" | Should -Be 'auth'
    }
}

Describe 'Invoke-CliProbe timeout' {
    It 'returns error when the command exceeds the timeout' {
        Invoke-CliProbe @('pwsh', '-NoProfile', '-Command', 'Start-Sleep 5') -TimeoutSec 1 | Should -Be 'error'
    }
    It 'classifies a fast command' {
        Invoke-CliProbe @('pwsh', '-NoProfile', '-Command', 'exit 0') | Should -Be 'ok'
    }
}

Describe 'Test-CliAvailability' {
    It 'reports not-installed when the command is absent' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'codex' }
        $r = Test-CliAvailability -Adapter ([PSCustomObject]@{ Name='codex'; Command='codex'; Probe={ param($ctx) 'ok' } })
        $r.Status | Should -Be 'not-installed'
    }
    It 'runs the probe when installed and returns its status' {
        Mock Get-Command { [PSCustomObject]@{ Source='C:\x\gemini.exe' } } -ParameterFilter { $Name -eq 'gemini' }
        $r = Test-CliAvailability -Adapter ([PSCustomObject]@{ Name='gemini'; Command='gemini'; Probe={ param($ctx) 'no-quota' } })
        $r.Status | Should -Be 'no-quota'
        $r.Cli    | Should -Be 'gemini'
    }
}

Describe 'Resolve-LaunchCli' {
    It 'returns the chosen CLI when it is available' {
        Resolve-LaunchCli -Chosen 'gemini' -Availability @{ gemini='ok'; claude='ok' } | Should -Be 'gemini'
    }
    It 'falls back to claude when the chosen CLI is unavailable' {
        Resolve-LaunchCli -Chosen 'gemini' -Availability @{ gemini='no-quota'; claude='ok' } | Should -Be 'claude'
    }
    It 'falls back to claude when the chosen CLI is missing from the map' {
        Resolve-LaunchCli -Chosen 'codex' -Availability @{ claude='ok' } | Should -Be 'claude'
    }
}

Describe 'Resolve-IssueCliMap' {
    It 'keeps a valid available choice' {
        $map = Resolve-IssueCliMap -Issues @(12,14) -Choices @{ 12='gemini'; 14='claude' } -Availability @{ gemini='ok'; claude='ok' }
        $map[12] | Should -Be 'gemini'
        $map[14] | Should -Be 'claude'
    }
    It 'coerces an unavailable choice to claude' {
        $map = Resolve-IssueCliMap -Issues @(12) -Choices @{ 12='codex' } -Availability @{ claude='ok' }
        $map[12] | Should -Be 'claude'
    }
    It 'defaults an unspecified issue to claude' {
        $map = Resolve-IssueCliMap -Issues @(99) -Choices @{} -Availability @{ claude='ok' }
        $map[99] | Should -Be 'claude'
    }
}
Describe 'Show-CliAvailability' {
    It 'renders one line per CLI with its status' {
        $out = Show-CliAvailability -Availability @{ claude='ok'; gemini='no-quota' } | Out-String
        $out | Should -Match 'claude'
        $out | Should -Match 'no-quota'
    }
}

Describe 'Build-FleetPlan' {
    It 'pairs each started issue with its resolved CLI' {
        $started = @(
            [PSCustomObject]@{ issue=12; repo='o/r'; branch='issue-12-x'; workPath='C:\wt\12' }
            [PSCustomObject]@{ issue=14; repo='o/r'; branch='issue-14-y'; workPath='C:\wt\14' }
        )
        $map = @{ 12='gemini'; 14='claude' }
        $plan = Build-FleetPlan -Started $started -CliMap $map
        ($plan | Where-Object issue -eq 12).cli | Should -Be 'gemini'
        ($plan | Where-Object issue -eq 14).cli | Should -Be 'claude'
    }
    It 'defaults to claude when an issue is absent from the map' {
        $started = @([PSCustomObject]@{ issue=7; repo='o/r'; branch='b'; workPath='C:\wt\7' })
        (Build-FleetPlan -Started $started -CliMap @{})[0].cli | Should -Be 'claude'
    }
}

Describe 'non-claude adapters' {
    It 'gemini BuildLaunch uses -p and --approval-mode yolo --skip-trust' {
        $ctx = @{ BriefingFile = 'C:\b\brief.txt' }
        $s = & ((Get-CliAdapters | Where-Object Name -eq 'gemini').BuildLaunch) $ctx
        $s | Should -Match 'gemini -p'
        $s | Should -Match '--approval-mode yolo'
        $s | Should -Match '--skip-trust'
    }
    It 'codex BuildLaunch uses exec + --dangerously-bypass-approvals-and-sandbox with an stdin EOF guard' {
        $ctx = @{ BriefingFile = 'C:\b\brief.txt' }
        $s = & ((Get-CliAdapters | Where-Object Name -eq 'codex').BuildLaunch) $ctx
        $s | Should -Match '\$null \|.*codex exec .*--dangerously-bypass-approvals-and-sandbox'
        $s | Should -Match 'Get-Content'
    }
    It 'codex Probe uses login status (not exec, which hangs on stdin)' {
        ((Get-CliAdapters | Where-Object Name -eq 'codex').Probe).ToString() | Should -Match 'login.*status'
    }
    It 'jules Probe scopes to remote list --session' {
        ((Get-CliAdapters | Where-Object Name -eq 'jules').Probe).ToString() | Should -Match 'remote.*list.*session'
    }
    It 'copilot BuildLaunch uses -p + --allow-all' {
        $ctx = @{ BriefingFile = 'C:\b\brief.txt' }
        (& ((Get-CliAdapters | Where-Object Name -eq 'copilot').BuildLaunch) $ctx) | Should -Match 'copilot -p .* --allow-all'
    }
    It 'jules BuildLaunch dispatches jules new' {
        $ctx = @{ BriefingFile = 'C:\b\brief.txt' }
        (& ((Get-CliAdapters | Where-Object Name -eq 'jules').BuildLaunch) $ctx) | Should -Match 'jules new'
    }
    It 'claude probe returns ok (host CLI always available)' {
        (& (Get-CliAdapters | Where-Object Name -eq 'claude').Probe $null) | Should -Be 'ok'
    }
    It 'briefing path with a single quote is escaped in a non-claude adapter' {
        $ctx = @{ BriefingFile = "C:\Users\O'Brien\b.txt" }
        (& ((Get-CliAdapters | Where-Object Name -eq 'gemini').BuildLaunch) $ctx) | Should -Match "O''Brien"
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
    It 'threads each page endCursor into the next fetch (first cursor is empty)' {
        $script:seen = @()
        $fetch = {
            param($cursor)
            $script:seen += "$cursor"
            if (-not $cursor) { @{ nodes = @('a'); hasNext = $true;  endCursor = 'NEXT' } }
            else              { @{ nodes = @('b'); hasNext = $false; endCursor = $null } }
        }
        Get-AllPages $fetch | Out-Null
        $script:seen[0] | Should -Be ''
        $script:seen[1] | Should -Be 'NEXT'
    }
    It 'returns an empty array for a single empty page' {
        @(Get-AllPages { param($c) @{ nodes = @(); hasNext = $false; endCursor = $null } }).Count | Should -Be 0
    }
    It 'finds an issue that only appears on the SECOND page (the #246 regression)' {
        $fetch = {
            param($cursor)
            if (-not $cursor) {
                @{ nodes = @([pscustomobject]@{ content = [pscustomobject]@{ __typename='Issue'; number=1 } }); hasNext = $true; endCursor = 'p2' }
            } else {
                @{ nodes = @([pscustomobject]@{ content = [pscustomobject]@{ __typename='Issue'; number=239 } }); hasNext = $false; endCursor = $null }
            }
        }
        $all = @(Get-AllPages $fetch)
        ($all | Where-Object { $_.content.number -eq 239 }).Count | Should -Be 1
    }
}
