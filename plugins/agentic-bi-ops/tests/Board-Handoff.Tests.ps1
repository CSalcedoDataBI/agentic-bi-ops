#Requires -Modules Pester
<#  Pester tests for Board-Handoff.ps1 - the /board handoff save driver.

    Board-Handoff.ps1 is side-effecting (gh + git + file writes), so it exposes a
    dot-source guard: with $env:ABIOS_HANDOFF_DOTSOURCE set, it returns right after
    defining the pure helpers, WITHOUT the token check or any gh/git/file side
    effect. These tests exercise only those pure helpers - zero network, zero I/O. #>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'scripts' 'Board-Handoff.ps1' | Resolve-Path
    $env:ABIOS_HANDOFF_DOTSOURCE = '1'
    . $script:Script
    $env:ABIOS_HANDOFF_DOTSOURCE = ''
}

Describe 'Get-HandoffBranchIssue' {
    It 'parses the issue number from an issue-<n>-slug branch' {
        Get-HandoffBranchIssue 'issue-139-build-board-handoff-save' | Should -Be 139
    }
    It 'returns 0 for a non-issue branch' {
        Get-HandoffBranchIssue 'main' | Should -Be 0
    }
    It 'returns 0 for an empty branch' {
        Get-HandoffBranchIssue '' | Should -Be 0
    }
}

Describe 'New-HandoffArchiveName (Windows-safe, colon-free)' {
    It 'produces a colon-free basic ISO-8601 UTC filename' {
        $name = New-HandoffArchiveName ([datetime]'2026-07-07T14:32:05Z')
        $name | Should -Not -Match ':'
        $name | Should -BeExactly '20260707T143205Z-handoff.md'
    }
    It 'keeps an explicit UTC DateTime stable (no double-conversion, timezone-independent)' {
        $utc  = New-HandoffArchiveName ([datetime]::new(2026,7,7,14,0,0,[DateTimeKind]::Utc))
        $utc | Should -BeExactly '20260707T140000Z-handoff.md'
    }
}

Describe 'Get-HandoffStamp (RFC3339 UTC)' {
    It 'stamps RFC3339 with a trailing Z' {
        Get-HandoffStamp ([datetime]'2026-07-07T14:32:05Z') | Should -BeExactly '2026-07-07T14:32:05Z'
    }
}

Describe 'Get-HandoffVerifiedRatio' {
    It 'counts [V] verified over total tagged claims' {
        Get-HandoffVerifiedRatio @('[V] a', '[V] b', '[?] c') | Should -Be '2/3'
    }
    It 'is 0/0 when nothing is tagged' {
        Get-HandoffVerifiedRatio @('plain line', 'another') | Should -Be '0/0'
    }
    It 'counts a leading tag after a "- " bullet' {
        Get-HandoffVerifiedRatio @('- [V] bulleted verified', '- [?] bulleted unknown') | Should -Be '1/2'
    }
    It 'ignores a mid-line tag (e.g. a gathered commit message about [V]/[?] tagging)' {
        # Regression: a commit message that literally contains "[V]/[?]" must NOT be
        # counted as two claims - only the one real leading [V] claim counts.
        $lines = @('[V] Recent commits:', '    - 55fe376 spec: [V]/[?] tagging protocol')
        Get-HandoffVerifiedRatio $lines | Should -Be '1/1'
    }
    It 'is all-verified when there are no [?]' {
        Get-HandoffVerifiedRatio @('[V] one', '[V] two') | Should -Be '2/2'
    }
}

Describe 'ConvertTo-HandoffFrontmatter' {
    It 'serializes an ordered dict between --- fences, preserving order' {
        $fm = [ordered]@{ issue = 139; repo = 'o/r'; pr = 'null' }
        $out = ConvertTo-HandoffFrontmatter $fm
        $out | Should -Match "(?s)^---.*issue: 139.*repo: o/r.*pr: null.*---$"
        ($out -split "`n")[0] | Should -Be '---'
        ($out -split "`n")[-1] | Should -Be '---'
    }
    It 'renders empty values as null' {
        $out = ConvertTo-HandoffFrontmatter ([ordered]@{ pr = '' })
        $out | Should -Match 'pr: null'
    }
}

Describe 'Format-HandoffMarkdown' {
    It 'omits sections with no content and bullet-prefixes bare lines' {
        $md = Format-HandoffMarkdown -Frontmatter '---' -Heading 'H' -GitBlock '' `
                -NextStep '[V] next' -Done @('did a thing') -OpenThreads @() -Traps @() -KeyFiles @()
        $md | Should -Match '## Next concrete step'
        $md | Should -Match '## Done this session'
        $md | Should -Match '- did a thing'
        $md | Should -Not -Match '## Open threads'
        $md | Should -Not -Match '## Traps'
        $md | Should -Not -Match '## Verified git state'
    }
    It 'does not double-prefix a line that already starts with a dash' {
        $md = Format-HandoffMarkdown -Frontmatter '---' -Heading 'H' -GitBlock '' `
                -NextStep '' -Done @('- already bulleted') -OpenThreads @() -Traps @() -KeyFiles @()
        $md | Should -Match '(?m)^- already bulleted$'
        $md | Should -Not -Match '- - already bulleted'
    }
    It 'includes the git block when provided' {
        $md = Format-HandoffMarkdown -Frontmatter '---' -Heading 'H' -GitBlock '[V] Branch: x' `
                -NextStep '' -Done @() -OpenThreads @() -Traps @() -KeyFiles @()
        $md | Should -Match '## Verified git state'
        $md | Should -Match '\[V\] Branch: x'
    }
}

Describe 'Add-GitignoreEntries (idempotent)' {
    It 'appends missing patterns' {
        $out = Add-GitignoreEntries "node_modules/`n" @('/HANDOFF.md', '/.handoffs/')
        $out | Should -Match '/HANDOFF.md'
        $out | Should -Match '/.handoffs/'
    }
    It 'is a no-op when all patterns already exist' {
        $body = "/HANDOFF.md`n/.handoffs/`n"
        Add-GitignoreEntries $body @('/HANDOFF.md', '/.handoffs/') | Should -BeExactly $body
    }
    It 'handles an empty starting body' {
        $out = Add-GitignoreEntries "" @('/HANDOFF.md')
        $out | Should -BeExactly "/HANDOFF.md`n"
    }
    It 'only adds the truly missing pattern' {
        $out = Add-GitignoreEntries "/HANDOFF.md`n" @('/HANDOFF.md', '/.handoffs/')
        ([regex]::Matches($out, '/HANDOFF\.md')).Count | Should -Be 1
        $out | Should -Match '/.handoffs/'
    }
}
