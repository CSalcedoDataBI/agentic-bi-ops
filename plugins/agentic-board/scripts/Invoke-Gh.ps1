<#  Invoke-Gh.ps1 - run gh so that a failure is a FAILURE, not an empty result (#303).

    Why this exists. `gh` signals failure ONLY through its exit code, and a native command
    that exits non-zero does NOT throw in PowerShell - not even under
    $ErrorActionPreference = 'Stop', which governs cmdlets only. So this:

        $fields = (gh project field-list 13 --owner x --format json | ConvertFrom-Json).fields

    turns a 401 into `$fields = @()`. Nothing errors, nothing warns, and the caller reads it
    as "the board has no fields" - which is exactly the premise it then WRITES from. That
    misread already shipped once: Board-Fill reported a healthy "no gaps" board it had never
    managed to read (issue #86). It was fixed in that one file and never generalised, which
    is why this is a shared helper and not another hand-written check.

    The contract, and both halves matter equally:
      * gh exits non-zero            -> throw, with the operation named and gh's stderr attached.
      * gh succeeds and returns []   -> return []. A genuinely empty board is NOT an error.
    If those two ever collapse into each other the helper has failed at its only job, so the
    test suite pins them as a pair.

    Three failure modes, not one:
      1. non-zero exit                        -> -GhArgs alone covers it.
      2. exit 0 with an unparseable/empty body -> -Json (gh --json always emits at least [] or {}).
      3. exit 0 with a graphql errors[] body   -> -Graphql. The request succeeded; the query did not.

    stderr is captured here rather than left to each call site, because the `2>$null` idiom
    that ~30 sites use hides the message AND the exit code goes unread, so the failure leaves
    no trace at all.

    Pure at load: dot-source it, it defines functions only (no gh, no output).
      . (Join-Path $PSScriptRoot 'Invoke-Gh.ps1')

    Usage:
      $board  = Invoke-Gh -GhArgs @('project','view','13','--owner','x','--format','json') `
                          -What 'leer el board #13' -Json
      $resp   = Invoke-Gh -GhArgs @('api','graphql','-f',"query=$q") -What 'mover el item' -Json -Graphql
      $null   = Invoke-Gh -GhArgs @('project','item-edit',...) -What 'escribir el campo' -Retries 3
#>

# The ONE place the gh executable is touched. A seam, so the retry/parse/throw logic above
# it is unit-testable by mocking this: no token, no network, any exit code on demand.
# stdout is kept CLEAN (stderr goes to its own file, never merged with 2>&1, which would
# splice ErrorRecords into a body about to be parsed as JSON).
function Invoke-GhRaw {
    param([string[]]$GhArgs)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $out  = & gh @GhArgs 2>$errFile
        $code = $LASTEXITCODE           # read FIRST: any native call after this clobbers it
        $err  = ''
        if (Test-Path $errFile) {
            # -Raw on an empty file returns $null, and ([string]$null).Trim() THROWS
            # ("cannot call a method on a null-valued expression") - so the empty-stderr
            # case, i.e. every successful call, has to be handled explicitly.
            $raw = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
            if ($raw) { $err = $raw.Trim() }
        }
        return [pscustomobject]@{ Output = $out; ExitCode = $code; StdErr = $err }
    } finally {
        Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    }
}

# Is this failure worth retrying? Only what retrying can actually fix: GitHub's transient
# 5xx and network stalls. A 401 or a 404 is a fact, and retrying it four times just makes
# the same error arrive later.
function Test-GhTransientError {
    param([string]$StdErr)
    if (-not $StdErr) { return $false }
    return ($StdErr -match 'HTTP 5\d\d' -or
            $StdErr -match 'i/o timeout' -or
            $StdErr -match 'connection reset' -or
            $StdErr -match 'TLS handshake timeout' -or
            $StdErr -match 'temporary failure')
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory)][string[]]$GhArgs,
        [string]$What = 'la operacion gh',
        [switch]$Json,
        [switch]$Graphql,
        [int]   $Retries = 0,
        [int]   $RetryDelayMs = 500
    )

    $attempt = 0
    while ($true) {
        $r = Invoke-GhRaw -GhArgs $GhArgs
        if ($r.ExitCode -eq 0) { break }

        # Retry only a transient failure, and only while attempts remain.
        if ($attempt -lt $Retries -and (Test-GhTransientError -StdErr $r.StdErr)) {
            $attempt++
            Start-Sleep -Milliseconds ($RetryDelayMs * $attempt)   # linear backoff
            continue
        }
        $detail = if ($r.StdErr) { ": $($r.StdErr)" } else { '' }
        throw "No pude $What (gh exit $($r.ExitCode))$detail"
    }

    if (-not $Json) { return $r.Output }

    # gh --json ALWAYS emits at least [] or {}. Nothing means something went wrong in a way
    # the exit code did not report - never hand that back as an empty result.
    $body = ($r.Output -join "`n").Trim()
    if (-not $body) { throw "No pude $What - gh salio 0 pero sin salida (se esperaba JSON)" }

    try   { $parsed = $body | ConvertFrom-Json }
    catch { throw "No pude $What - la respuesta de gh no es JSON valido: $($_.Exception.Message)" }

    # graphql's own failure mode: HTTP 200 + exit 0, with the failure inside the body.
    if ($Graphql -and $parsed.PSObject.Properties.Name -contains 'errors' -and @($parsed.errors).Count -gt 0) {
        throw "No pude $What - graphql devolvio errores: $(@($parsed.errors)[0].message)"
    }
    return $parsed
}
