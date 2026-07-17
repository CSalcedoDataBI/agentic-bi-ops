#Requires -Modules Pester
<#  Tests for Backup-Board.ps1 and Export-BoardSnapshot.ps1 (#312, part of #303).

    These two are the ugliest instance of the silent-gh bug. Every other victim misreports
    something you can see; a backup misreports on the one day you cannot afford it. Before
    this, a 401 produced three empty files and printed "Backup OK:".

    HOW THESE RUN. Both scripts are top-level commands with mandatory params, so they cannot
    be dot-sourced for mocking, and stubbing Invoke-GhRaw from the outside does not work
    either: the script dot-sources Invoke-Gh.ps1 into its OWN scope afterwards, which shadows
    the stub (the first draft of this file did exactly that and silently called the real API).

    So the seam is a fake `gh.cmd` placed first on PATH. It is more faithful than any mock:
    the real script, the real Invoke-Gh, the real Invoke-GhRaw and its real 2>$errFile
    redirection all run - only the binary at the end is ours. #>

BeforeAll {
    $script:Backup   = (Join-Path $PSScriptRoot '..' 'scripts' 'Backup-Board.ps1'         | Resolve-Path).Path
    $script:Snapshot = (Join-Path $PSScriptRoot '..' 'scripts' 'Export-BoardSnapshot.ps1' | Resolve-Path).Path

    # A fake gh: exits with %FAKE_GH_EXIT%, prints %FAKE_GH_OUT% on stdout and %FAKE_GH_ERR%
    # on stderr. With %FAKE_GH_FAIL_ON% set it counts calls in %FAKE_GH_COUNT% and fails only
    # on the Nth - which is how the read-then-write ordering gets pinned.
    $script:FakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('fakegh' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $script:FakeDir -Force | Out-Null
    @'
@echo off
setlocal EnableDelayedExpansion
set N=0
if defined FAKE_GH_COUNT (
  if exist "%FAKE_GH_COUNT%" set /p N=<"%FAKE_GH_COUNT%"
  set /a N=!N!+1
  echo !N!>"%FAKE_GH_COUNT%"
)
if defined FAKE_GH_FAIL_ON if "!N!"=="%FAKE_GH_FAIL_ON%" (
  if defined FAKE_GH_FAIL_ERR (echo %FAKE_GH_FAIL_ERR% 1>&2) else (echo HTTP 401: Bad credentials 1>&2)
  exit /b 1
)
if defined FAKE_GH_ERR echo %FAKE_GH_ERR% 1>&2
if defined FAKE_GH_OUT echo %FAKE_GH_OUT%
if defined FAKE_GH_EXIT (exit /b %FAKE_GH_EXIT%)
exit /b 0
'@ | Set-Content (Join-Path $script:FakeDir 'gh.cmd') -Encoding ASCII

    # Run a script with the fake gh first on PATH, in a CHILD pwsh so PATH/env never leak.
    # $Params are NAMED script parameters: only the VALUE is quoted, because quoting the
    # name too makes PowerShell bind '-Number' as a positional value ("cannot convert
    # '-Number' to Int32") - which fails the script before gh is ever reached, and makes
    # every "must not write a file" test pass for the wrong reason.
    function Invoke-WithFakeGh {
        param([string]$Path, [hashtable]$Params, [hashtable]$Env = @{})
        $envSet = ($Env.GetEnumerator() | ForEach-Object { "`$env:$($_.Key)='$($_.Value)'" }) -join '; '
        $argStr = ($Params.GetEnumerator() | ForEach-Object { "-$($_.Key) '$($_.Value)'" }) -join ' '
        $cmd = "`$env:PATH='$($script:FakeDir);' + `$env:PATH; $envSet; & '$Path' $argStr"
        return (& pwsh -NoProfile -Command $cmd 2>&1 | Out-String)
    }
}

AfterAll { Remove-Item $script:FakeDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Backup-Board: a failed read must not become an empty backup' {
    BeforeEach {
        $script:Dir   = Join-Path ([System.IO.Path]::GetTempPath()) ('bkp' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Count = Join-Path ([System.IO.Path]::GetTempPath()) ('cnt' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
    }
    AfterEach {
        Remove-Item $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:Count -Force -ErrorAction SilentlyContinue
    }

    It 'writes NOTHING and fails when gh returns 401' {
        $out = Invoke-WithFakeGh -Path $script:Backup -Params @{ Number = 13; Owner = 'o'; BackupDir = $script:Dir } `
                                 -Env @{ FAKE_GH_EXIT = '1'; FAKE_GH_ERR = 'HTTP 401: Bad credentials' }
        # THE assertion: no plausible-looking file survived the failure.
        @(Get-ChildItem $script:Dir -File).Count | Should -Be 0
        $out | Should -Not -Match 'Backup OK'
        $out | Should -Match 'Bad credentials'      # and the buried stderr is surfaced
    }

    It 'fails when gh exits 0 with an EMPTY body (the exit code cannot catch this one)' {
        $out = Invoke-WithFakeGh -Path $script:Backup -Params @{ Number = 13; Owner = 'o'; BackupDir = $script:Dir } `
                                 -Env @{ FAKE_GH_EXIT = '0' }
        @(Get-ChildItem $script:Dir -File).Count | Should -Be 0
        $out | Should -Not -Match 'Backup OK'
    }

    It 'writes NOTHING when the THIRD read fails - no half-backup left behind' {
        # Why every read happens before any write. A partial backup is the worst artefact of
        # all: it exists, so nobody re-runs it.
        #
        # The injected failure is a 401 ON PURPOSE. With a 502 the helper retries and the
        # backup legitimately SUCCEEDS - which is what the first version of this test hit,
        # asserting 0 files against a run that had correctly recovered. See the retry test
        # below: same injection point, transient error, opposite (and also correct) outcome.
        $out = Invoke-WithFakeGh -Path $script:Backup -Params @{ Number = 13; Owner = 'o'; BackupDir = $script:Dir } `
                                 -Env @{ FAKE_GH_OUT = '{"title":"My Board"}'; FAKE_GH_COUNT = $script:Count; FAKE_GH_FAIL_ON = '3' }
        @(Get-ChildItem $script:Dir -File).Count | Should -Be 0
        $out | Should -Not -Match 'Backup OK'
    }

    It 'RECOVERS from a transient 502 on the third read and still writes the backup' {
        # The other half of -Retries: a 5xx must not cost you the backup.
        $out = Invoke-WithFakeGh -Path $script:Backup -Params @{ Number = 13; Owner = 'o'; BackupDir = $script:Dir } `
                                 -Env @{ FAKE_GH_OUT     = '{"title":"My Board"}'
                                         FAKE_GH_COUNT   = $script:Count
                                         FAKE_GH_FAIL_ON = '3'
                                         FAKE_GH_FAIL_ERR = 'HTTP 502: Bad gateway' }
        $out | Should -Match 'Backup OK'
        @(Get-ChildItem $script:Dir -File).Count | Should -Be 3
    }

    It 'writes three NON-EMPTY files and reports OK on success' {
        $out = Invoke-WithFakeGh -Path $script:Backup -Params @{ Number = 13; Owner = 'o'; BackupDir = $script:Dir } `
                                 -Env @{ FAKE_GH_OUT = '{"title":"My Board"}' }
        $out | Should -Match 'Backup OK'
        $files = @(Get-ChildItem $script:Dir -File)
        $files.Count | Should -Be 3
        @($files | Where-Object { $_.Length -eq 0 }).Count | Should -Be 0
        # -RawJson, not a re-serialisation: a backup is persisted verbatim.
        (Get-Content $files[0].FullName -Raw).Trim() | Should -Be '{"title":"My Board"}'
    }
}

Describe 'Export-BoardSnapshot: a failed read must not become a "0 of 0 done" report' {
    BeforeEach { $script:OutFile = Join-Path ([System.IO.Path]::GetTempPath()) ('snap' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.md') }
    AfterEach  { Remove-Item $script:OutFile -Force -ErrorAction SilentlyContinue }

    It 'writes no file and fails when gh returns 401' {
        # The pre-fix behaviour published "_0 of 0 tracked items done._" - a document that
        # reads like a finished board rather than a failed read.
        $out = Invoke-WithFakeGh -Path $script:Snapshot -Params @{ Number = 13; Owner = 'o'; OutFile = $script:OutFile } `
                                 -Env @{ FAKE_GH_EXIT = '1'; FAKE_GH_ERR = 'HTTP 401: Bad credentials' }
        Test-Path $script:OutFile | Should -BeFalse
        $out | Should -Not -Match 'Snapshot written'
    }

    It 'renders the board on success' {
        $out = Invoke-WithFakeGh -Path $script:Snapshot -Params @{ Number = 13; Owner = 'o'; OutFile = $script:OutFile } `
                                 -Env @{ FAKE_GH_OUT = '{"items":[{"title":"a thing","status":"Done","content":{"number":7,"url":"u"}}]}' }
        Test-Path $script:OutFile | Should -BeTrue
        $md = Get-Content $script:OutFile -Raw
        $md | Should -Match '1 of 1 tracked items done'
        $md | Should -Match '#7'
    }
}
