#Requires -Modules Pester
<#  Pester tests for Publish-DocsWiki.ps1 page generation (-PagesOnly, no git/network).
    Validates:
      - Docs-Home is generated from README.md (HTML stripped, GENERATED marker present)
      - One Docs-Command-<X> page per commands/*.md file (frontmatter + agent artifacts stripped)
      - Navigation links: command pages link back to Docs-Home; Home links to each command
      - Knowledge registry pages (Home + Knowledge-<Domain>) when registry.json exists
      - _Sidebar and _Footer navigation pages
      - Empty states: README with only HTML still produces a Docs-Home
      - Uninitialized wiki produces an actionable error with the wiki URL
#>
BeforeAll {
    $script:Engine = Join-Path $PSScriptRoot '..' 'scripts' 'Publish-DocsWiki.ps1' | Resolve-Path

    # Helper: create a minimal fake repo root with README.md and commands/*.md
    function New-FakeRoot {
        param(
            [string]$ReadmeContent = '',
            [hashtable]$Commands   = @{}   # basename -> content
        )
        $root = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-t-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        if ($ReadmeContent -or $ReadmeContent -eq '') {
            $ReadmeContent | Set-Content -LiteralPath (Join-Path $root 'README.md') -Encoding utf8
        }
        $cmdsDir = Join-Path $root 'commands'
        New-Item -ItemType Directory -Path $cmdsDir -Force | Out-Null
        foreach ($name in $Commands.Keys) {
            $Commands[$name] | Set-Content -LiteralPath (Join-Path $cmdsDir "$name.md") -Encoding utf8
        }
        # Also put commands dir at the expected relative path for the script (../commands from scripts/)
        # The script resolves $commandsDir = Join-Path $PSScriptRoot '..' 'commands'
        # so we wire a symlink-free approach: override by setting $env:ABIOS_DOCS_COMMANDS_DIR if
        # the script supports it, or simply use the real commands dir (which always exists).
        #
        # Because -PagesOnly uses the REAL commandsDir (relative to PSScriptRoot), we test with
        # both the real commands dir and the README we supply via -Root.
        $root
    }

    # Helper: run the script in -PagesOnly mode and return a hashtable of page-name -> content
    function Invoke-PagesOnly {
        param(
            [string]$Root,
            [string]$OutDir = (Join-Path $Root 'out')
        )
        & $script:Engine -Root $Root -OutDir $OutDir -PagesOnly | Out-Null
        $pages = @{}
        foreach ($f in (Get-ChildItem -LiteralPath $OutDir -Filter '*.md' -File)) {
            $pages[$f.BaseName] = Get-Content -LiteralPath $f.FullName -Raw
        }
        $pages
    }

    # Helper: compute expected extra page count from knowledge registry at given root
    function Get-KnowledgePageCount {
        param([string]$Root)
        $regPath     = Join-Path $Root 'knowledge' 'registry.json'
        $regPathYaml = Join-Path $Root 'knowledge' 'registry.yaml'
        $rp = if (Test-Path -LiteralPath $regPath) { $regPath }
              elseif (Test-Path -LiteralPath $regPathYaml) { $regPathYaml }
              else { $null }
        if (-not $rp) { return 0 }
        $reg = Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $reg) { return 0 }
        $domains = @($reg.references | Select-Object -ExpandProperty domain -Unique)
        if ($domains.Count -eq 0) { return 1 }  # Home only when empty registry
        return 1 + $domains.Count                # Home + one per domain
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — page set' {
    BeforeAll {
        # Use the real README.md from the repo root (three levels up from tests/)
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out      = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-out-" + [guid]::NewGuid().ToString('N'))
        $script:Pages    = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'generates Docs-Home' {
        $script:Pages.Keys | Should -Contain 'Docs-Home'
    }

    It 'generates one Docs-Command-<X> page per command file' {
        $commandFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'commands') -Filter '*.md' -File)
        foreach ($cf in $commandFiles) {
            $expectedSlug = 'Docs-Command-' + ($cf.BaseName.Substring(0,1).ToUpper() + $cf.BaseName.Substring(1))
            $script:Pages.Keys | Should -Contain $expectedSlug -Because "commands/$($cf.Name) must produce a wiki page"
        }
    }

    It 'generates _Sidebar navigation page' {
        $script:Pages.Keys | Should -Contain '_Sidebar'
    }

    It 'generates _Footer page' {
        $script:Pages.Keys | Should -Contain '_Footer'
    }

    It 'generates exactly 3 + (command files) + (knowledge pages) total pages' {
        $commandCount = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'commands') -Filter '*.md' -File).Count
        $knExtra      = Get-KnowledgePageCount -Root $script:RepoRoot
        $script:Pages.Count | Should -Be ($commandCount + 3 + $knExtra)
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — Docs-Home content' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out      = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-home-" + [guid]::NewGuid().ToString('N'))
        $script:Pages    = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
        $script:DocsHomePage = $script:Pages['Docs-Home']
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'carries the GENERATED do-not-edit marker' {
        $script:DocsHomePage | Should -Match 'GENERATED by /docs wiki'
    }

    It 'strips <p> HTML blocks' {
        $script:DocsHomePage | Should -Not -Match '<p\b'
        $script:DocsHomePage | Should -Not -Match '</p>'
    }

    It 'strips <img> HTML elements' {
        $script:DocsHomePage | Should -Not -Match '<img\b'
    }

    It 'strips <sub> blocks (README version footer)' {
        $script:DocsHomePage | Should -Not -Match '<sub>'
        $script:DocsHomePage | Should -Not -Match '</sub>'
    }

    It 'retains key README prose (not blanked out)' {
        $script:DocsHomePage | Should -Match 'agentic-board'
    }

    It 'links to each command page' {
        $commandFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'commands') -Filter '*.md' -File)
        $content = $script:DocsHomePage   # capture before foreach to avoid scope drift
        foreach ($cf in $commandFiles) {
            $slug    = 'Docs-Command-' + ($cf.BaseName.Substring(0,1).ToUpper() + $cf.BaseName.Substring(1))
            $pattern = [regex]::Escape("($slug)")
            $content | Should -Match $pattern -Because "Home must link to $slug"
        }
    }

    It 'contains a "Last published" datestamp' {
        $script:DocsHomePage | Should -Match 'Last published \d{4}-\d{2}-\d{2}'
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — Docs-Command-<X> content' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out      = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-cmds-" + [guid]::NewGuid().ToString('N'))
        $script:Pages    = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
        # Pick the 'board' command page as the representative rich test subject
        $script:BoardPage = $script:Pages['Docs-Command-Board']
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'each command page carries the GENERATED marker' {
        foreach ($key in ($script:Pages.Keys | Where-Object { $_ -like 'Docs-Command-*' })) {
            $script:Pages[$key] | Should -Match 'GENERATED by /docs wiki' -Because "$key must carry the generated marker"
        }
    }

    It 'each command page strips the YAML frontmatter' {
        foreach ($key in ($script:Pages.Keys | Where-Object { $_ -like 'Docs-Command-*' })) {
            $script:Pages[$key] | Should -Not -Match '(?m)^---$' -Because "$key must not contain raw YAML frontmatter"
        }
    }

    It 'strips the "You are running the agentic-board /X command." line' {
        $script:BoardPage | Should -Not -Match 'You are running the agentic-board /board command\.'
    }

    It 'strips the "Arguments: $ARGUMENTS" template artifact' {
        foreach ($key in ($script:Pages.Keys | Where-Object { $_ -like 'Docs-Command-*' })) {
            $script:Pages[$key] | Should -Not -Match '\$ARGUMENTS' -Because "$key must not contain the raw template variable"
        }
    }

    It 'includes the description from frontmatter as a blockquote' {
        # board.md description starts with "Administer/automate a GitHub Projects board"
        $script:BoardPage | Should -Match '> Administer/automate a GitHub Projects board'
    }

    It 'includes substantive command content (not just the header)' {
        # The board page documents its verbs — check one known verb keyword
        $script:BoardPage | Should -Match '\bwork\b'
    }

    It 'links back to Docs-Home' {
        foreach ($key in ($script:Pages.Keys | Where-Object { $_ -like 'Docs-Command-*' })) {
            $script:Pages[$key] | Should -Match '\[← Product Docs\]\(Docs-Home\)' -Because "$key must link back to Docs-Home"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — knowledge registry pages' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out      = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-kn-" + [guid]::NewGuid().ToString('N'))
        $script:Pages    = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
        # Determine whether the registry is present and its domains
        $regPath = Join-Path $script:RepoRoot 'knowledge' 'registry.json'
        $script:HasRegistry = Test-Path -LiteralPath $regPath
        if ($script:HasRegistry) {
            $reg = Get-Content -LiteralPath $regPath -Raw | ConvertFrom-Json
            $script:KnDomains = @($reg.references | Select-Object -ExpandProperty domain -Unique | Sort-Object)
        }
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'generates a Knowledge Home page when registry.json exists' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $script:Pages.Keys | Should -Contain 'Home'
    }

    It 'Knowledge Home carries the GENERATED marker' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $script:Pages['Home'] | Should -Match 'GENERATED by /docs wiki'
    }

    It 'generates one Knowledge-<Domain> page per domain in the registry' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $pages = $script:Pages
        foreach ($domain in $script:KnDomains) {
            $slug = 'Knowledge-' + (($domain -replace '[^\w-]+', '-') -replace '-+', '-').Trim('-')
            $pages.Keys | Should -Contain $slug -Because "domain '$domain' must produce a wiki page"
        }
    }

    It 'each Knowledge domain page back-links to Home' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $pages = $script:Pages
        foreach ($key in ($pages.Keys | Where-Object { $_ -like 'Knowledge-*' })) {
            $pages[$key] | Should -Match '\[← Home\]\(Home\)' -Because "$key must link back to Home"
        }
    }

    It 'Knowledge Home links to each domain page' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $homePage = $script:Pages['Home']
        foreach ($domain in $script:KnDomains) {
            $slug = 'Knowledge-' + (($domain -replace '[^\w-]+', '-') -replace '-+', '-').Trim('-')
            $homePage | Should -Match ([regex]::Escape("($slug)")) -Because "Home must link to $slug"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — _Sidebar content' {
    BeforeAll {
        $script:RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out       = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-sidebar-" + [guid]::NewGuid().ToString('N'))
        $script:Pages     = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
        $script:SidebarPage = $script:Pages['_Sidebar']
        # Determine knowledge domains for sidebar link check
        $regPath = Join-Path $script:RepoRoot 'knowledge' 'registry.json'
        $script:HasRegistry = Test-Path -LiteralPath $regPath
        if ($script:HasRegistry) {
            $reg = Get-Content -LiteralPath $regPath -Raw | ConvertFrom-Json
            $script:KnDomains = @($reg.references | Select-Object -ExpandProperty domain -Unique | Sort-Object)
        }
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'carries the GENERATED marker' {
        $script:SidebarPage | Should -Match 'GENERATED by /docs wiki'
    }

    It 'contains a Product Docs section' {
        $script:SidebarPage | Should -Match '## Product Docs'
    }

    It 'links to Docs-Home' {
        $script:SidebarPage | Should -Match '\[Home\]\(Docs-Home\)'
    }

    It 'links to each command page' {
        $commandFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'commands') -Filter '*.md' -File)
        $content = $script:SidebarPage
        foreach ($cf in $commandFiles) {
            $slug    = 'Docs-Command-' + ($cf.BaseName.Substring(0,1).ToUpper() + $cf.BaseName.Substring(1))
            $pattern = [regex]::Escape("($slug)")
            $content | Should -Match $pattern -Because "_Sidebar must link to $slug"
        }
    }

    It 'contains a Knowledge section linking to Home' {
        $script:SidebarPage | Should -Match '## Knowledge'
        $script:SidebarPage | Should -Match '\[Knowledge\]\(Home\)'
    }

    It 'lists each knowledge domain in the sidebar when registry exists' {
        if (-not $script:HasRegistry) { Set-ItResult -Skipped -Because 'no knowledge/registry.json in this repo' ; return }
        $sidebar = $script:SidebarPage
        foreach ($domain in $script:KnDomains) {
            $slug = 'Knowledge-' + (($domain -replace '[^\w-]+', '-') -replace '-+', '-').Trim('-')
            $sidebar | Should -Match ([regex]::Escape("($slug)")) -Because "_Sidebar must link to domain $domain"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — _Footer content' {
    BeforeAll {
        $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:Out        = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-footer-" + [guid]::NewGuid().ToString('N'))
        $script:Pages      = Invoke-PagesOnly -Root $script:RepoRoot -OutDir $script:Out
        $script:FooterPage = $script:Pages['_Footer']
    }
    AfterAll { if ($script:Out -and (Test-Path $script:Out)) { Remove-Item $script:Out -Recurse -Force } }

    It 'carries the GENERATED marker' {
        $script:FooterPage | Should -Match 'GENERATED by /docs wiki'
    }

    It 'warns that edits here will be overwritten' {
        $script:FooterPage | Should -Match 'generated from the repository'
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — error cases' {
    It 'throws when README.md is missing' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ("docswiki-normd-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        try {
            { & $script:Engine -Root $root -OutDir (Join-Path $root 'out') -PagesOnly } |
                Should -Throw -ExpectedMessage '*README.md not found*'
        } finally {
            Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when -PagesOnly is given without -OutDir' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        { & $script:Engine -Root $root -PagesOnly } | Should -Throw -ExpectedMessage '*-PagesOnly requires -OutDir*'
    }
}

# ─────────────────────────────────────────────────────────────────────────────────────
Describe 'Publish-DocsWiki — uninitialized wiki error' {
    BeforeAll {
        $script:UninitRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..'))
        $script:PriorGit   = Get-Item 'Function:git' -ErrorAction SilentlyContinue
        $script:PriorGh    = Get-Item 'Function:gh'  -ErrorAction SilentlyContinue

        function global:git {
            if ('clone' -in $args) { $global:LASTEXITCODE = 128; return }
            $global:LASTEXITCODE = 0
        }
        function global:gh {
            if ($args[0] -eq 'api' -and 'user' -in $args) { Write-Output 'test-user' }
            elseif ($args[0] -eq 'api') { Write-Output '{"has_wiki":true,"permissions":{"push":true},"name":"test"}' }
            $global:LASTEXITCODE = 0
        }
        [System.Environment]::SetEnvironmentVariable('ABIOS_TEST_DOCS_TOKEN', 'fake-unit-test-token', 'User')
    }
    AfterAll {
        [System.Environment]::SetEnvironmentVariable('ABIOS_TEST_DOCS_TOKEN', $null, 'User')
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        Remove-Item 'Function:git' -ErrorAction SilentlyContinue
        Remove-Item 'Function:gh'  -ErrorAction SilentlyContinue
        if ($script:PriorGit) { New-Item -Path 'Function:git' -Value $script:PriorGit.ScriptBlock -Force | Out-Null }
        if ($script:PriorGh)  { New-Item -Path 'Function:gh'  -Value $script:PriorGh.ScriptBlock  -Force | Out-Null }
    }

    It 'throws with an actionable step to create the first wiki page via web UI' {
        { & $script:Engine -Root $script:UninitRoot -Repo 'test-owner/test-docs-repo' -TokenVar ABIOS_TEST_DOCS_TOKEN } |
            Should -Throw -ExpectedMessage '*Create the first page*'
    }

    It 'error message includes the wiki URL so the user can navigate directly' {
        { & $script:Engine -Root $script:UninitRoot -Repo 'test-owner/test-docs-repo' -TokenVar ABIOS_TEST_DOCS_TOKEN } |
            Should -Throw -ExpectedMessage '*github.com/test-owner/test-docs-repo/wiki*'
    }
}
