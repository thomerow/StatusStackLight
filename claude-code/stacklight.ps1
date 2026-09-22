<#
.SYNOPSIS
    Drives the stack light (StatusStackLight) from Claude Code hooks.

.DESCRIPTION
    The stack light shows a STATE, the hooks deliver EVENTS. This script sits
    in between: every session stores its state as a file under
    ~/.claude/stacklight, and all fresh files together determine what the five
    lamps show.

    This solves two problems a direct hook-to-HTTP wiring would have:
      * Several parallel sessions would switch each other off.
      * A crashed session would leave the stack light lit forever
        (hence the freshness check via StaleMinutes).

    Every run sends the complete target state, even if nothing has changed.
    That way the next hook heals any deviation - whether caused by an ESP
    restart, the web interface or curl. It costs one POST, and nothing
    flickers: the blink and pulse phase follows the device's common clock, not
    the time of the request.

    Display:
      white   ready       session open, nothing going on    dim, breathes very slowly
      green   done        just finished                     steady
      blue    working     Claude is thinking/working        slow pulse
      orange  asking      a question for you                steady
      orange  waiting     needs an approval  <- the important one  blinking
      red     error       something went wrong              latched until the
                                                            next prompt

    Exactly ONE of ready/done/working/asking/waiting is lit (priority from
    right to left); red sits on top independently.

    The difference between green and white is time: green means "the result
    is fresh", white means "has been sitting there a while" or "just opened".
    After DoneMinutes, green falls back to white. Since no hook may fire after
    that, Stop starts a background straggler (-Event Tick) that recomputes
    once when the time is up.

    Orange goes off again as soon as the approved tool has run
    (PostToolUse -> -Event ToolDone). Without that it would stay lit after an
    approval until the end of the response - an approval is not a new prompt.

    Session states in the files: idle (opened), working, asking (question),
    waiting (approval), done.

.PARAMETER Event
    SessionStart | UserPromptSubmit | Approval | Question | ToolDone |
    Stop | StopFailure | ToolFailure | SessionEnd | Danger | Tick |
    SelfTest | AllOff | Status

.NOTES
    Called as a Claude Code hook with async=true and therefore does not block
    the agent. The script ALWAYS exits with exit code 0 - a broken lamp must
    never hold up the work.

    Requires the firmware from firmware/ in this repo (API /api/lamps).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    # 'Freigabe' and 'Rueckfrage' are the former German names of Approval and
    # Question, still accepted until every settings.json has been migrated.
    [ValidateSet('SessionStart', 'UserPromptSubmit', 'Approval', 'Question',
                 'ToolDone', 'Stop', 'StopFailure', 'ToolFailure', 'SessionEnd',
                 'Danger', 'Tick', 'SelfTest', 'AllOff', 'Status',
                 'Freigabe', 'Rueckfrage')]
    [string] $Event,

    # Only for -Event Tick: wait this long first.
    [int]    $WaitSeconds = 0,

    [string] $SessionId,
    [string] $BaseUrl      = $(if ($env:STACKLIGHT_URL) { $env:STACKLIGHT_URL } else { 'http://statusstacklight' }),

    # Older than this -> the session counts as crashed and is forgotten.
    [int]    $StaleMinutes = 60,

    # For this long after finishing, green shows "freshly done", then it falls
    # back to white.
    [int]    $DoneMinutes  = 5,

    [double] $FlashSeconds = 1.2,
    [switch] $Quiet
)

$ErrorActionPreference = 'Continue'

switch ($Event) {
    'Freigabe'   { $Event = 'Approval' }
    'Rueckfrage' { $Event = 'Question' }
}

$StateDir  = Join-Path $HOME '.claude\stacklight'
$LogFile   = Join-Path $StateDir '_error.log'

# Order as on the stack light from top to bottom - only for the output of
# -Event Status.
$LAMPS = 'red', 'orange', 'green', 'blue', 'white'

# ---------------------------------------------------------------------------
#  Display
# ---------------------------------------------------------------------------
#
# This is the place to adjust how the stack light looks - nowhere else.
#
# The brightness values are matched to each other, not equal: the white lamp
# is by far the brightest and needs much less percent than the others to look
# equally bright. As a steady light around 12 % is enough, so it does not
# bother you from the corner of your eye in the evening; breathing, it needs a
# higher peak, see ready.
#
# frequency is the blink or pulse rate in Hz, duty the share of the period
# during which a blinking lamp is lit.

$Display = [ordered]@{
    # Base state: a session is open, nothing is happening right now.
    # Breathes very slowly instead of staying steady: a light that burns for
    # hours eventually gets tuned out - breathing keeps it readable as "still
    # alive" without restlessness. Calmer than the blue working pulse, so the
    # two are not confused. 30 % is the peak of the breath.
    ready   = @{ lamp = 'white';  effect = 'pulse';  brightness = 30; frequency = 0.15 }

    # Freshly done. Calm and without motion - there is nothing to do, there is
    # just something to read.
    done    = @{ lamp = 'green';  effect = 'steady'; brightness = 45 }

    # Claude is working. Slow pulsing, because it is motion without
    # restlessness: you see from the corner of your eye that it is running,
    # but you are not being called. 0.3 Hz is a good three seconds per breath.
    working = @{ lamp = 'blue';   effect = 'pulse';  brightness = 70; frequency = 0.3 }

    # Claude has a question. Orange, because it is waiting for you; steady
    # rather than blinking, so you can tell from afar whether it is a question
    # or an approval.
    asking  = @{ lamp = 'orange'; effect = 'steady'; brightness = 40 }

    # Waiting for an approval - the important state, because the work stands
    # still until then. Hard blinking instead of pulsing: this one SHOULD call
    # you. The attention comes from the blinking, not from the brightness - at
    # 100 %, orange is unpleasantly glaring up close.
    waiting = @{ lamp = 'orange'; effect = 'blink';  brightness = 40; frequency = 1.2; duty = 55 }

    # Error. Sits on top of everything else independently and stays latched
    # until the next prompt.
    error   = @{ lamp = 'red';    effect = 'steady'; brightness = 100 }
}

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

function Write-Log([string] $Message) {
    try {
        "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message |
            Add-Content -Path $LogFile -Encoding utf8
    } catch { }
}

# Claude Code passes the hook a JSON object on stdin. IsInputRedirected keeps
# the script from waiting for EOF on an interactive console.
function Read-HookInput {
    try {
        if ([Console]::IsInputRedirected) {
            $raw = [Console]::In.ReadToEnd()
            if ($raw -and $raw.Trim()) { return ($raw | ConvertFrom-Json) }
        }
    } catch { Write-Log "could not read stdin: $_" }
    return $null
}

# Second, exact check for the warning flash. The "if" conditions in
# settings.json are only a rough pre-filter: commands that Claude Code cannot
# parse cleanly (loops, $(...), heredocs) are let through to be safe - even
# `for i in 1; do echo "$(echo harmless)"; done` passes the pre-filter. A
# warning flash that comes for harmless commands trains you to stop looking.
# Hence this look at the actual command text.
#
# Without hook input (manual call, -Event Danger for testing) it flashes.
$DangerousCommands = @(
    '\brm\s+(-\w*\s+)*-\w*([rR]\w*f|f\w*[rR])'     # rm -rf, -fr, -Rf, -rfv ...
    '\bgit\s+push\b.*\s(--force\b|-f\b)'
    '\bgit\s+reset\s+--hard\b'
    '\bgit\s+clean\s+-\w*f'
)

function Test-Dangerous {
    param($HookInput)
    $command = $null
    try { $command = "$($HookInput.tool_input.command)" } catch { }
    if (-not $command) { return $true }
    foreach ($pattern in $DangerousCommands) {
        if ($command -cmatch $pattern) { return $true }
    }
    return $false
}

function Resolve-SessionId {
    param($HookInput)
    if ($SessionId) { return $SessionId }
    if ($HookInput -and $HookInput.PSObject.Properties.Name -contains 'session_id') {
        $id = "$($HookInput.session_id)"
        if ($id) { return ($id -replace '[^A-Za-z0-9_.-]', '_') }
    }
    if ($env:CLAUDE_SESSION_ID) { return ($env:CLAUDE_SESSION_ID -replace '[^A-Za-z0-9_.-]', '_') }
    # Fallback name: the stack light keeps working, but all parallel sessions
    # then share a single file. See -Event Status.
    return 'default'
}

function Set-SessionState {
    param([string] $Id, [string] $State, [Nullable[bool]] $ErrorFlag = $null)

    $file = Join-Path $StateDir "$Id.json"
    $cur  = $null
    if (Test-Path $file) { try { $cur = Get-Content $file -Raw | ConvertFrom-Json } catch { } }

    $obj = [ordered]@{
        state = if ($State) { $State } elseif ($cur) { $cur.state } else { 'idle' }
        error = if ($null -ne $ErrorFlag) { [bool] $ErrorFlag }
                elseif ($cur) { [bool] $cur.error } else { $false }
        ts    = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $obj | ConvertTo-Json -Compress | Set-Content -Path $file -Encoding utf8
}

function Remove-SessionState {
    param([string] $Id)
    $file = Join-Path $StateDir "$Id.json"
    if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

function Get-SessionState {
    param([string] $Id)
    $file = Join-Path $StateDir "$Id.json"
    if (-not (Test-Path $file)) { return $null }
    try { return (Get-Content $file -Raw | ConvertFrom-Json).state } catch { return $null }
}

# Green should fall back to white by itself after DoneMinutes. But after a
# Stop, no hook may fire for a long time - so Stop starts a straggler that
# waits out the time and then recomputes once.
#
# Only one ever runs: a new Stop ends the previous one. That is right with
# several sessions too, because the most recent Stop is the one whose green
# lasts longest; older ones have expired by then anyway. PID and start time
# are kept in _timer.json, so a foreign process that happens to have
# inherited the PID of a long-finished straggler is never hit.
function Start-DoneTimer {
    if ($DoneMinutes -le 0) { return }
    $timerFile = Join-Path $StateDir '_timer.json'

    if (Test-Path $timerFile) {
        try {
            $old = Get-Content $timerFile -Raw | ConvertFrom-Json
            $p   = Get-Process -Id $old.pid -ErrorAction Stop
            if ($p.StartTime.ToUniversalTime().Ticks -eq [int64] $old.start) {
                Stop-Process -Id $old.pid -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    $wait = $DoneMinutes * 60 + 2
    $p = Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
            -ArgumentList @('-NoProfile', '-File', "`"$PSCommandPath`"",
                            '-Event', 'Tick', '-WaitSeconds', $wait, '-BaseUrl', $BaseUrl,
                            '-DoneMinutes', $DoneMinutes, '-StaleMinutes', $StaleMinutes)
    @{ pid = $p.Id; start = $p.StartTime.ToUniversalTime().Ticks } |
        ConvertTo-Json -Compress | Set-Content -Path $timerFile -Encoding utf8
}

# Builds a lamp state from an entry of the display table.
#
# The fields are filled in for lamps that are off, too: the firmware keeps
# effect and brightness across switching off, and the web interface then does
# not show 100 % / steady everywhere as soon as you turn a lamp on by hand.
function New-Lamp {
    param([hashtable] $Spec, [bool] $On)

    return [ordered]@{
        on         = $On
        effect     = $(if ($Spec.effect) { $Spec.effect } else { 'steady' })
        brightness = [int]    $(if ($null -ne $Spec.brightness) { $Spec.brightness } else { 100 })
        frequency  = [double] $(if ($null -ne $Spec.frequency)  { $Spec.frequency }  else { 1.0 })
        duty       = [int]    $(if ($null -ne $Spec.duty)       { $Spec.duty }       else { 50 })
    }
}

# Which of the states is lit right now? Returns the key from $Display, or
# $null if no session is open at all.
function Get-MainState {
    $now       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $staleEdge = $now - ($StaleMinutes * 60)
    $doneEdge  = $now - ($DoneMinutes  * 60)
    $sessions  = @()

    foreach ($f in (Get-ChildItem -Path $StateDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '_*') { continue }        # skip helper files
        try { $s = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if (-not $s -or $s.ts -lt $staleEdge) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue   # crashed session
            continue
        }
        $sessions += $s
    }

    $open    = $sessions.Count -gt 0
    $waiting = @($sessions | Where-Object { $_.state -eq 'waiting' }).Count -gt 0
    $asking  = @($sessions | Where-Object { $_.state -eq 'asking'  }).Count -gt 0
    $working = @($sessions | Where-Object { $_.state -eq 'working' }).Count -gt 0
    # Only 'done' counts as done, and only while it is fresh. 'idle' (freshly
    # opened session) deliberately falls through to 'ready'.
    # -gt, not -ge: otherwise -DoneMinutes 0 would not mean "never green" but
    # "green as long as the timestamp falls into the same second".
    $done    = @($sessions | Where-Object { $_.state -eq 'done' -and $_.ts -gt $doneEdge }).Count -gt 0
    $failed  = @($sessions | Where-Object { $_.error }).Count -gt 0

    $main = if     ($waiting) { 'waiting' }
            elseif ($asking)  { 'asking'  }
            elseif ($working) { 'working' }
            elseif ($done)    { 'done'    }
            elseif ($open)    { 'ready'   }
            else              { $null     }

    return [pscustomobject]@{ Main = $main; Error = $failed }
}

# Complete target state of all five lamps.
#
# All five are always described, never just the changed ones. That costs
# nothing (a single request sets all of them) and repairs any deviation
# caused by manual switching or an ESP restart along the way.
function Get-Lamps {
    $situation = Get-MainState

    $target = [ordered]@{}
    foreach ($name in $LAMPS) { $target[$name] = New-Lamp -Spec @{} -On $false }

    # Two states share orange (asking/waiting). An entry that is off must not
    # overwrite one of the same lamp that is on - otherwise the order of the
    # table would decide whether orange comes on at all.
    $claimed = @{}
    foreach ($state in $Display.Keys) {
        $spec = $Display[$state]
        $on   = if ($state -eq 'error') { $situation.Error } else { $state -eq $situation.Main }
        if ($claimed[$spec.lamp] -and -not $on) { continue }
        $target[$spec.lamp] = New-Lamp -Spec $spec -On $on
        if ($on) { $claimed[$spec.lamp] = $true }
    }

    return $target
}

# One request for all five lamps. The firmware applies them atomically -
# either everything fits or nothing changes.
function Send-Lamps {
    param($Target)

    $json = ConvertTo-Json -InputObject $Target -Depth 4 -Compress
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/lamps" -Method Post -Body $json `
                          -ContentType 'application/json' -TimeoutSec 2 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Log "POST /api/lamps failed: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
try {
    if (-not (Test-Path $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }

    # The straggler waits BEFORE the mutex - otherwise it would sit on it for
    # five minutes and block every other hook.
    if ($Event -eq 'Tick' -and $WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }

    # PostToolUse fires after every tool call, so very often. As a rule the
    # session is not waiting then, and there is nothing to do - get out right
    # away, without the mutex and without a request to the stack light.
    if ($Event -eq 'ToolDone') {
        $hook = Read-HookInput
        $sid  = Resolve-SessionId -HookInput $hook
        if ((Get-SessionState -Id $sid) -notin @('waiting', 'asking')) { exit 0 }
    }

    # Serialise all writes and HTTP calls: several sessions can fire at the
    # same time, and two parallel runs would overtake each other - the older
    # state might then arrive last.
    $mutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeStacklight')
    $held  = $false
    try { $held = $mutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $held = $true }

    if ($Event -ne 'ToolDone') {
        $hook = Read-HookInput
        $sid  = Resolve-SessionId -HookInput $hook
    }

    switch ($Event) {
        # 'idle', not 'done': a freshly opened session is ready, but nothing
        # has finished - otherwise the stack light would turn green just from
        # opening a terminal.
        'SessionStart'     { Set-SessionState -Id $sid -State 'idle'    -ErrorFlag $false }
        # A new prompt acknowledges an old error - otherwise red would stay forever.
        'UserPromptSubmit' { Set-SessionState -Id $sid -State 'working' -ErrorFlag $false }
        # The distinction comes from separate hook entries in settings.json
        # (matchers on the notification type or the tool name), not from
        # fields of the hook input - their structure is not documented for
        # Notification.
        'Approval'         { Set-SessionState -Id $sid -State 'waiting' }
        'Question'         { Set-SessionState -Id $sid -State 'asking' }
        # The tool has run (approved, or question answered) - Claude keeps
        # working.
        'ToolDone'         { Set-SessionState -Id $sid -State 'working' }
        'Stop'             { Set-SessionState -Id $sid -State 'done';   Start-DoneTimer }
        'StopFailure'      { Set-SessionState -Id $sid -State 'done'    -ErrorFlag $true; Start-DoneTimer }
        'ToolFailure'      { Set-SessionState -Id $sid -ErrorFlag $true }
        'SessionEnd'       { Remove-SessionState -Id $sid }
        'AllOff'           { Get-ChildItem $StateDir -Filter '*.json' -File -EA SilentlyContinue |
                                Remove-Item -Force -EA SilentlyContinue }
    }

    switch ($Event) {
        'Status' {
            $situation = Get-MainState
            $target    = Get-Lamps

            'State   : {0}{1}' -f $(if ($situation.Main) { $situation.Main } else { 'no session open' }),
                                  $(if ($situation.Error) { ' + error' } else { '' }) | Write-Output
            'Light   : {0}' -f $BaseUrl | Write-Output
            '' | Write-Output

            foreach ($name in $LAMPS) {
                $l = $target[$name]
                if ($l.on) {
                    $how = switch ($l.effect) {
                        'blink' { 'blinking {0:0.#} Hz, {1} % duty' -f $l.frequency, $l.duty }
                        'pulse' { 'pulsing {0:0.#} Hz'              -f $l.frequency }
                        default { 'steady' }
                    }
                    '{0,-7} ON  {1,3} %  {2}' -f $name, $l.brightness, $how | Write-Output
                } else {
                    '{0,-7} --' -f $name | Write-Output
                }
            }

            # Be honest: green only falls back to white by itself thanks to
            # the straggler. If none is running (computer was asleep, process
            # killed), it only changes on the next event.
            if ($situation.Main -eq 'done') {
                $running = $false
                try {
                    $t = Get-Content (Join-Path $StateDir '_timer.json') -Raw | ConvertFrom-Json
                    $running = (Get-Process -Id $t.pid -EA Stop).StartTime.ToUniversalTime().Ticks -eq [int64] $t.start
                } catch { }
                '' | Write-Output
                if ($running) { 'Note    : straggler running, green switches to white by itself.' | Write-Output }
                else          { 'Note    : no straggler, green only switches on the next event.' | Write-Output }
            }
        }

        'SelfTest' {
            # The firmware runs the channel sweep itself and restores the
            # previous state afterwards. A target state sent while it runs
            # would be lost - so wait and only set it afterwards.
            $waitTime = 6.0
            try {
                $r = Invoke-RestMethod -Uri "$BaseUrl/api/sweep" -TimeoutSec 2 -ErrorAction Stop
                if ($r.channels -and $r.holdMs) { $waitTime = ($r.channels * $r.holdMs / 1000.0) + 0.5 }
            } catch {
                Write-Log "GET /api/sweep failed: $($_.Exception.Message)"
                $waitTime = 0
            }
            if ($waitTime -gt 0) { Start-Sleep -Seconds $waitTime }
            Send-Lamps -Target (Get-Lamps) | Out-Null
        }

        # Red warning flash for a dangerous command. Fast blinking instead of a
        # steady light, so it differs from the latched error red, and laid over
        # the main state instead of replacing it - blue keeps pulsing meanwhile.
        #
        # "Before" is only partly true: the PreToolUse hook does fire before
        # execution, but runs with async=true, and starting pwsh.exe alone
        # takes about 300 ms (measured). The flash is therefore effectively in
        # parallel with the command. That is only early enough to look up
        # while an approval is still pending - for an already approved command
        # you see it while it is already running.
        'Danger' {
            if (-not (Test-Dangerous -HookInput $hook)) { break }
            $flash = Get-Lamps
            $flash['red'] = New-Lamp -On $true `
                -Spec @{ effect = 'blink'; brightness = 100; frequency = 6.0; duty = 50 }
            Send-Lamps -Target $flash | Out-Null
            Start-Sleep -Seconds $FlashSeconds
            Send-Lamps -Target (Get-Lamps) | Out-Null
        }

        default {
            $ok = Send-Lamps -Target (Get-Lamps)
            if (-not $Quiet) { Write-Verbose ("lamps set: " + $ok) }
        }
    }
}
catch {
    Write-Log "unexpected error for Event=$Event : $_"
}
finally {
    if ($held -and $mutex) { try { $mutex.ReleaseMutex() } catch { } }
    if ($mutex) { $mutex.Dispose() }
}

exit 0
