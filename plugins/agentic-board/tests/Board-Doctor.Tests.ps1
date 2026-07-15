#Requires -Modules Pester
<#  Pester tests for Board-Doctor.ps1 - the git-reality branch/worktree audit (#274).

    The whole point of the command is that it does NOT trust `git branch --merged` (this repo
    squash-merges, so a merged branch is never an ancestor of main - the #273 trap, PR #275)
    and does NOT trust `sessions.json` (a process registry, not a ref inventory). So the tests
    pin exactly that: the merge verdict comes from the PR state AND the head OID matching the
    local tip, and the registry can only ever protect a branch, never define one.

    Everything under test is pure: the classifier takes every fact as an argument, so no git,
    no gh and no token are needed.

    The syntax check that used to live here (the "limite de $PrLimit:" trap that broke every run)
    now covers every script in the plugin, in Scripts.Parse.Tests.ps1 (#282). #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Doctor.ps1' | Resolve-Path
    # The doctor dot-sources Board-Work.ps1 for Get-SessionCompletion; both guards must be set
    # so neither script runs its main entry (or demands a token).
    $env:ABIOS_DOCTOR_DOTSOURCE   = '1'
    . $script:Script
    $env:ABIOS_DOCTOR_DOTSOURCE   = ''

    $script:Now = [datetime]'2026-07-15T12:00:00'
    $script:Tip = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:Other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

    function New-Pr {
        param([int]$Number = 1, [string]$State = 'MERGED', [string]$HeadRefOid = $script:Tip)
        [pscustomobject]@{ number = $Number; state = $State; headRefOid = $HeadRefOid }
    }
    # A branch classified with sensible defaults; every test overrides only what it is about.
    function Invoke-Classify {
        param([hashtable]$With = @{})
        $args = @{
            Name = 'issue-9-thing'; Tip = $script:Tip; Prs = @()
            CommitDate = $script:Now.AddDays(-1); Now = $script:Now; StaleDays = 30
        }
        foreach ($k in $With.Keys) { $args[$k] = $With[$k] }
        Get-BranchClass @args
    }
}

Describe 'Board-Doctor dot-source contract' {
    It 'reuses Get-SessionCompletion from Board-Work instead of re-implementing the merge verdict' {
        # If this ever fails, someone copied the verdict into the doctor and the two can drift.
        Get-Command Get-SessionCompletion -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It 'defines its pure helpers without touching git, gh or the token' {
        Get-Command Get-BranchClass     -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Get-WorktreeRecords -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Select-BranchPr     -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Board-Doctor parameter binding survives the dot-source' {
    # Regression: dot-sourcing Board-Work.ps1 runs ITS param() block in our scope, which reset
    # every shared parameter name to Board-Work's default. -DryRun became $false, so
    # `-Fix -DryRun` printed "DRY-RUN" and then really deleted branches. Caught by running it.
    It 'shares parameter names with Board-Work, so the clobbering risk is real and must stay covered' {
        $doctor = (Get-Command $script:Script).Parameters.Keys
        $work   = (Get-Command (Join-Path $PSScriptRoot '..' 'scripts' 'Board-Work.ps1' | Resolve-Path)).Parameters.Keys
        $shared = @($doctor | Where-Object { $work -contains $_ -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters })
        # If this ever drops to zero the restore is dead code and can go; today it is not.
        $shared | Should -Contain 'DryRun'
        $shared | Should -Contain 'Repo'
    }
    It 'replays $PSBoundParameters after the dot-source so the caller binding wins' {
        # Source-level, on purpose: the fix is top-level script code (not a function), and the
        # end-to-end proof needs a real repo + gh, which the rest of this suite deliberately
        # never touches. Verified by hand against the live repo: `-Fix -DryRun` over 57
        # merged branches left 62/62 branches intact.
        $src = Get-Content $script:Script -Raw
        $src | Should -Match 'foreach \(\$k in \$PSBoundParameters\.Keys\)'
        # The replay must sit in the `finally` of the dot-source, i.e. BEFORE anything reads
        # $DryRun/$Fix. If someone moves it below the first use, the guard is decorative.
        $replayAt = $src.IndexOf('$PSBoundParameters.Keys')
        $firstUse = $src.IndexOf('if ($DryRun)')
        $replayAt | Should -BeGreaterThan 0
        $replayAt | Should -BeLessThan $firstUse
    }
    It 'fails closed on every source it cannot vouch for' {
        # No PRs must never read as "nothing is merged" (that would reclassify every merged
        # branch as stale and offer 57 to -Fix); an empty branch/worktree inventory must never
        # read as "nothing to clean"; and an unreadable registry must never read as "no live
        # sessions" (that would strip a live branch of its veto). Raised by the Codex review
        # of PR #280 - each of these failed OPEN before.
        $src = Get-Content $script:Script -Raw
        $src | Should -Match 'if \(\$LASTEXITCODE -ne 0 -or \$null -eq \$prJson\)'   # gh pr list
        $src | Should -Match "'git for-each-ref' fallo"                              # branch inventory
        $src | Should -Match "'git worktree list' fallo"                             # worktree inventory
        $src | Should -Match 'if \(-not \$registryTrusted\)'                         # registry veto
    }
}

Describe 'Get-WorktreeRecords (porcelain parsing)' {
    It 'parses a normal worktree record' {
        $r = Get-WorktreeRecords -Porcelain "worktree C:/repo`nHEAD abc`nbranch refs/heads/issue-1-x`n"
        $r.Count       | Should -Be 1
        $r[0].Path     | Should -Be 'C:/repo'
        $r[0].Branch   | Should -Be 'issue-1-x'
        $r[0].Prunable | Should -BeNullOrEmpty
    }
    It 'parses several blank-line separated records' {
        $p = "worktree C:/a`nHEAD 111`nbranch refs/heads/one`n`nworktree C:/b`nHEAD 222`nbranch refs/heads/two`n"
        $r = Get-WorktreeRecords -Porcelain $p
        $r.Count      | Should -Be 2
        $r[1].Branch  | Should -Be 'two'
    }
    It 'captures the prunable reason git reports for a ghost worktree' {
        # This is the "worktree path gone" case - taken from git, never guessed.
        $r = Get-WorktreeRecords -Porcelain "worktree C:/gone`nHEAD abc`nbranch refs/heads/dead`nprunable gitdir file points to non-existent location`n"
        $r[0].Prunable | Should -Be 'gitdir file points to non-existent location'
    }
    It 'handles a detached and a bare worktree without inventing a branch' {
        $r = Get-WorktreeRecords -Porcelain "worktree C:/d`nHEAD abc`ndetached`n`nworktree C:/bare`nbare`n"
        $r[0].Detached | Should -BeTrue
        $r[0].Branch   | Should -BeNullOrEmpty
        $r[1].Bare     | Should -BeTrue
    }
    It 'returns nothing for empty input rather than throwing' {
        (Get-WorktreeRecords -Porcelain '').Count | Should -Be 0
    }
    It 'tolerates CRLF line endings' {
        $r = Get-WorktreeRecords -Porcelain "worktree C:/a`r`nHEAD 111`r`nbranch refs/heads/one`r`n"
        $r[0].Branch | Should -Be 'one'
    }
}

Describe 'Select-BranchPr (which PR speaks for this tip)' {
    It 'prefers the PR whose head IS our tip over the newest one' {
        # The -TakeOver trap: a newer PR on a reused branch name must not outrank the real one.
        $prs = @((New-Pr -Number 9 -HeadRefOid $script:Tip), (New-Pr -Number 99 -HeadRefOid $script:Other))
        (Select-BranchPr -Prs $prs -Tip $script:Tip).number | Should -Be 9
    }
    It 'falls back to the newest PR when none matches the tip' {
        $prs = @((New-Pr -Number 9 -HeadRefOid $script:Other), (New-Pr -Number 99 -HeadRefOid $script:Other))
        (Select-BranchPr -Prs $prs -Tip $script:Tip).number | Should -Be 99
    }
    It 'returns nothing when the branch has no PR at all' {
        Select-BranchPr -Prs @() -Tip $script:Tip | Should -BeNullOrEmpty
    }
}

Describe 'Get-BranchClass (the merge verdict)' {
    It 'classifies a MERGED PR whose head is our tip as merged and deletable' {
        $r = Invoke-Classify @{ Prs = @(New-Pr -Number 7 -State 'MERGED' -HeadRefOid $script:Tip) }
        $r.Class     | Should -Be 'merged'
        $r.Deletable | Should -BeTrue
        $r.Pr        | Should -Be 7
    }
    It 'does NOT trust a MERGED PR whose head is a different commit' {
        # The exact trap: an old merged PR must not vouch for commits it never contained.
        $r = Invoke-Classify @{ Prs = @(New-Pr -State 'MERGED' -HeadRefOid $script:Other) }
        $r.Class     | Should -Be 'merged-advanced'
        $r.Deletable | Should -BeFalse
    }
    It 'never marks an OPEN PR branch deletable' {
        $r = Invoke-Classify @{ Prs = @(New-Pr -State 'OPEN' -HeadRefOid $script:Tip) }
        $r.Class     | Should -Be 'in-review'
        $r.Deletable | Should -BeFalse
    }
    It 'surfaces a CLOSED unmerged PR for a decision, never for auto-deletion' {
        $r = Invoke-Classify @{ Prs = @(New-Pr -State 'CLOSED' -HeadRefOid $script:Tip) }
        $r.Class     | Should -Be 'closed-unmerged'
        $r.Deletable | Should -BeFalse
    }
    It 'ignores ancestry entirely: a squash-merged branch is merged only because the PR says so' {
        # There is no ancestry input at all. This test documents that on purpose: if someone
        # adds a `--merged` signal, they must change this contract deliberately.
        (Get-Command Get-BranchClass).Parameters.Keys | Should -Not -Contain 'Merged'
        (Get-Command Get-BranchClass).Parameters.Keys | Should -Not -Contain 'IsAncestor'
    }
}

Describe 'Get-BranchClass (branches with no PR)' {
    It 'classifies a branch older than StaleDays as stale' {
        $r = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-45) }
        $r.Class     | Should -Be 'stale'
        $r.AgeDays   | Should -Be 45
        $r.Deletable | Should -BeFalse
    }
    It 'classifies a recent branch as working, not stale' {
        $r = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-3) }
        $r.Class | Should -Be 'working'
    }
    It 'respects a custom StaleDays threshold' {
        $r = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-10); StaleDays = 5 }
        $r.Class | Should -Be 'stale'
    }
    It 'does not call a branch stale exactly at the threshold' {
        $r = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-30); StaleDays = 30 }
        $r.Class | Should -Be 'working'
    }
    It 'reports a dirty worktree as an expected keep (#276), not as stale' {
        $r = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-99); Dirty = 'dirty' }
        $r.Class     | Should -Be 'dirty'
        $r.Deletable | Should -BeFalse
    }
    It 'fails closed: an unreadable worktree is never treated as clean' {
        $r = Invoke-Classify @{ Dirty = 'unknown' }
        $r.Class | Should -Be 'dirty'
        $r.Reason | Should -Match 'no pude comprobar'
    }
}

Describe 'Get-WorktreeDirtyState (the last guard before --force)' {
    # Raised by the Codex review of PR #280: the dangerous side-effect paths were not pinned.
    It 'reports a clean worktree as clean' {
        Get-WorktreeDirtyState -ExitCode 0 -StatusLines @() | Should -Be 'clean'
    }
    It 'reports any status output as dirty' {
        Get-WorktreeDirtyState -ExitCode 0 -StatusLines @('?? scratch.txt') | Should -Be 'dirty'
    }
    It 'treats a git failure as unknown, never clean' {
        Get-WorktreeDirtyState -ExitCode 128 -StatusLines @() | Should -Be 'unknown'
    }
    It 'treats a missing worktree directory as unknown, never clean' {
        Get-WorktreeDirtyState -ExitCode 0 -StatusLines @() -PathExists $false | Should -Be 'unknown'
    }
    It 'is not fooled by whitespace-only output' {
        Get-WorktreeDirtyState -ExitCode 0 -StatusLines @('', '   ') | Should -Be 'clean'
    }
    It 'asks git for ALL untracked files rather than inheriting status.showUntrackedFiles' {
        # With `status.showUntrackedFiles=no` a bare --porcelain calls a worktree full of
        # untracked scratch files CLEAN, and the removal runs --force. Pin the flag at the call.
        $src = Get-Content $script:Script -Raw
        $src | Should -Match 'status --porcelain --untracked-files=all'
    }
}

Describe 'Get-BranchClass (the session registry may only protect)' {
    It 'marks a branch with a live session as active and never deletable' {
        $r = Invoke-Classify @{ HasLiveSession = $true; CommitDate = $script:Now.AddDays(-99) }
        $r.Class     | Should -Be 'active'
        $r.Deletable | Should -BeFalse
    }
    It 'refuses to delete even a proven-merged branch while a session is live on it' {
        # The registry cannot create work, but it must be able to veto destroying it.
        $r = Invoke-Classify @{ Prs = @(New-Pr -State 'MERGED' -HeadRefOid $script:Tip); HasLiveSession = $true }
        $r.Class     | Should -Be 'merged'
        $r.Deletable | Should -BeFalse
    }
    It 'classifies identically with and without the registry when no session is live' {
        # sessions.json is not an input to what EXISTS - only to what is protected.
        $a = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-45); HasLiveSession = $false }
        $b = Invoke-Classify @{ CommitDate = $script:Now.AddDays(-45) }
        $a.Class | Should -Be $b.Class
    }
}

Describe 'Get-DoctorClassOrder (report contract)' {
    It 'lists merged first - the bulk of the pile and the only safely deletable class' {
        (Get-DoctorClassOrder)[0].Class | Should -Be 'merged'
    }
    It 'covers every class the classifier can emit' {
        # Guards against a new class being invented but never rendered.
        $rendered = @((Get-DoctorClassOrder).Class)
        foreach ($c in @('merged','merged-advanced','in-review','closed-unmerged','active','dirty','stale','working')) {
            $rendered | Should -Contain $c
        }
    }
}
