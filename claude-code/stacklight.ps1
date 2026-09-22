<#
.SYNOPSIS
    Steuert die Signalsaeule (StatusStackLight) aus Claude-Code-Hooks heraus.

.DESCRIPTION
    Die Saeule zeigt einen ZUSTAND, die Hooks liefern EREIGNISSE. Dazwischen
    liegt dieses Skript: jede Session legt ihren Zustand als Datei unter
    ~/.claude/stacklight ab, und aus allen frischen Dateien wird berechnet, was
    die fuenf Lampen anzeigen.

    Das loest zwei Probleme, die eine direkte Verdrahtung von Hook zu HTTP hat:
      * Mehrere parallele Sessions wuerden sich gegenseitig ausknipsen.
      * Eine abgestuerzte Session liesse die Saeule fuer immer leuchten
        (deshalb der Frischetest ueber StaleMinutes).

    Gesendet wird bei jedem Lauf der komplette Sollzustand, auch wenn er sich
    nicht geaendert hat. So heilt der naechste Hook jede Abweichung - ob durch
    einen Neustart des ESP, das Web-Interface oder curl. Das kostet einen POST,
    und es flackert nichts: Blink- und Pulsphase haengen an der gemeinsamen
    Uhr des Geraets, nicht am Zeitpunkt der Anfrage.

    Anzeige:
      weiss   bereit      Session offen, nichts los         schwach, atmet sehr langsam
      gruen   fertig      gerade fertig geworden            ruhig
      blau    arbeitet    Claude denkt/arbeitet             langsam pulsierend
      orange  fragt       Rueckfrage an dich                ruhig
      orange  wartet      braucht eine Freigabe  <- der wichtige  blinkend
      rot     Fehler      etwas ging schief                 rastet bis zum
                                                            naechsten Prompt

    Genau EINE von bereit/fertig/arbeitet/fragt/wartet brennt (Rangfolge von
    rechts nach links); Rot liegt unabhaengig darueber.

    Der Unterschied zwischen gruen und weiss ist zeitlich: gruen heisst "das
    Ergebnis ist frisch", weiss heisst "liegt schon eine Weile" oder "gerade
    erst geoeffnet". Nach FertigMinuten faellt gruen auf weiss zurueck. Weil
    danach womoeglich kein Hook mehr feuert, startet Stop dafuer einen
    Nachzuegler im Hintergrund (-Event Tick), der nach Ablauf einmal neu
    rechnet.

    Orange geht wieder aus, sobald das freigegebene Werkzeug gelaufen ist
    (PostToolUse -> -Event ToolDone). Ohne das bliebe es nach einer Freigabe
    bis zum Ende der Antwort stehen - eine Freigabe ist kein neuer Prompt.

    Sessionzustaende in den Dateien: idle (geoeffnet), working, asking
    (Rueckfrage), waiting (Freigabe), done.

.PARAMETER Event
    SessionStart | UserPromptSubmit | Freigabe | Rueckfrage | ToolDone |
    Stop | StopFailure | ToolFailure | SessionEnd | Danger | Tick |
    SelfTest | AllOff | Status

.NOTES
    Wird als Claude-Code-Hook mit async=true aufgerufen und blockiert den
    Agenten daher nicht. Das Skript beendet sich IMMER mit Exit-Code 0 -
    eine kaputte Lampe darf niemals die Arbeit aufhalten.

    Braucht die Firmware aus firmware/ in diesem Repo (API /api/lamps).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('SessionStart', 'UserPromptSubmit', 'Freigabe', 'Rueckfrage',
                 'ToolDone', 'Stop', 'StopFailure', 'ToolFailure', 'SessionEnd',
                 'Danger', 'Tick', 'SelfTest', 'AllOff', 'Status')]
    [string] $Event,

    # Nur fuer -Event Tick: so lange vorher warten.
    [int]    $WarteSekunden = 0,

    [string] $SessionId,
    [string] $BaseUrl      = $(if ($env:STACKLIGHT_URL) { $env:STACKLIGHT_URL } else { 'http://statusstacklight' }),

    # Aelter als das -> die Session gilt als abgestuerzt und wird vergessen.
    [int]    $StaleMinutes = 60,

    # So lange nach dem Fertigwerden zeigt gruen "frisch fertig", danach faellt
    # es auf weiss zurueck.
    [int]    $FertigMinuten = 5,

    [double] $FlashSeconds = 1.2,
    [switch] $Quiet
)

$ErrorActionPreference = 'Continue'

$StateDir  = Join-Path $HOME '.claude\stacklight'
$LogFile   = Join-Path $StateDir '_error.log'

# Reihenfolge wie an der Saeule von oben nach unten - nur fuer die Ausgabe von
# -Event Status.
$LAMPEN = 'red', 'orange', 'green', 'blue', 'white'

# ---------------------------------------------------------------------------
#  Anzeige
# ---------------------------------------------------------------------------
#
# Hier wird geschraubt, wenn die Saeule anders aussehen soll - sonst nirgends.
#
# Die Helligkeiten sind aneinander angeglichen, nicht gleich: die weisse Lampe
# ist mit Abstand die hellste und braucht deutlich weniger Prozent als die
# uebrigen, um gleich hell zu wirken. Als Dauerlicht reichen ihr um 12 %,
# damit sie abends im Augenwinkel nicht stoert; atmend braucht sie einen
# hoeheren Gipfel, siehe bereit.
#
# frequency ist der Blink- bzw. Pulsiertakt in Hz, duty der Anteil der Periode,
# in dem eine blinkende Lampe leuchtet.

$Anzeige = [ordered]@{
    # Grundzustand: eine Session steht offen, es passiert gerade nichts.
    # Atmet sehr langsam statt dauerhaft zu leuchten: ein Standlicht, das
    # stundenlang brennt, blendet man irgendwann aus - das Atmen haelt es als
    # "lebt noch" lesbar, ohne Unruhe. Ruhiger als das blaue Arbeiten, damit
    # die beiden nicht verwechselt werden. 30 % sind der Gipfel des Atemzugs.
    bereit   = @{ lampe = 'white';  effect = 'pulse';  brightness = 30; frequency = 0.15 }

    # Frisch fertig. Ruhig und ohne Bewegung - es ist nichts zu tun, es liegt
    # nur etwas zum Lesen da.
    fertig   = @{ lampe = 'green';  effect = 'steady'; brightness = 45 }

    # Claude arbeitet. Langsames Pulsieren, weil es Bewegung ohne Unruhe ist:
    # man sieht aus dem Augenwinkel, dass es laeuft, wird aber nicht
    # angesprochen. 0,3 Hz sind gut drei Sekunden je Atemzug.
    arbeitet = @{ lampe = 'blue';   effect = 'pulse';  brightness = 70; frequency = 0.3 }

    # Claude hat eine Rueckfrage. Orange, weil es auf dich wartet; dauerhaft
    # statt blinkend, damit man schon von weitem sieht, ob es eine Frage oder
    # eine Freigabe ist.
    fragt    = @{ lampe = 'orange'; effect = 'steady'; brightness = 40 }

    # Wartet auf eine Freigabe - der wichtige Zustand, denn bis dahin steht
    # die Arbeit still. Hartes Blinken statt Pulsieren: das hier SOLL dich
    # ansprechen. Die Aufmerksamkeit kommt vom Blinken, nicht von der
    # Helligkeit - mit 100 % ist Orange aus der Naehe unangenehm grell.
    wartet   = @{ lampe = 'orange'; effect = 'blink';  brightness = 50; frequency = 1.2; duty = 55 }

    # Fehler. Liegt unabhaengig ueber allem anderen und rastet bis zum
    # naechsten Prompt.
    fehler   = @{ lampe = 'red';    effect = 'steady'; brightness = 100 }
}

# ---------------------------------------------------------------------------
#  Hilfsfunktionen
# ---------------------------------------------------------------------------

function Write-Log([string] $Message) {
    try {
        "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message |
            Add-Content -Path $LogFile -Encoding utf8
    } catch { }
}

# Claude Code reicht dem Hook ein JSON-Objekt auf stdin. IsInputRedirected
# verhindert, dass das Skript an einer interaktiven Konsole auf EOF wartet.
function Read-HookInput {
    try {
        if ([Console]::IsInputRedirected) {
            $raw = [Console]::In.ReadToEnd()
            if ($raw -and $raw.Trim()) { return ($raw | ConvertFrom-Json) }
        }
    } catch { Write-Log "stdin nicht lesbar: $_" }
    return $null
}

# Zweite, genaue Pruefung fuer den Warnblitz. Die "if"-Bedingungen in
# settings.json sind nur ein grober Vorfilter: Befehle, die Claude Code nicht
# sauber zerlegen kann (Schleifen, $(...), Heredocs), laesst es sicherheitshalber
# durch - schon `for i in 1; do echo "$(echo harmlos)"; done` passiert den
# Vorfilter. Ein Warnblitz, der bei harmlosen Befehlen kommt, gewoehnt einem das
# Hinsehen ab. Deshalb hier der Blick auf den tatsaechlichen Befehlstext.
#
# Ohne Hook-Eingabe (Aufruf von Hand, -Event Danger zum Testen) wird geblitzt.
$GefaehrlicheBefehle = @(
    '\brm\s+(-\w*\s+)*-\w*([rR]\w*f|f\w*[rR])'     # rm -rf, -fr, -Rf, -rfv ...
    '\bgit\s+push\b.*\s(--force\b|-f\b)'
    '\bgit\s+reset\s+--hard\b'
    '\bgit\s+clean\s+-\w*f'
)

function Test-Gefaehrlich {
    param($HookInput)
    $befehl = $null
    try { $befehl = "$($HookInput.tool_input.command)" } catch { }
    if (-not $befehl) { return $true }
    foreach ($muster in $GefaehrlicheBefehle) {
        if ($befehl -cmatch $muster) { return $true }
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
    # Notfallname: die Saeule funktioniert weiter, nur laufen dann alle
    # parallelen Sessions in einer Datei zusammen. Siehe -Event Status.
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

# Gruen soll nach FertigMinuten von selbst auf weiss fallen. Nach einem Stop
# feuert aber womoeglich lange kein Hook mehr - also startet Stop einen
# Nachzuegler, der die Zeit absitzt und dann einmal neu rechnet.
#
# Es laeuft immer nur einer: ein neuer Stop beendet den vorigen. Das ist auch
# bei mehreren Sessions richtig, denn der juengste Stop ist der, dessen Gruen
# am laengsten gilt; aeltere sind bis dahin ohnehin abgelaufen. PID und
# Startzeit stehen in _timer.json, damit nie ein fremder Prozess erwischt
# wird, der zufaellig die PID eines laengst beendeten Nachzueglers geerbt hat.
function Start-FertigTimer {
    if ($FertigMinuten -le 0) { return }
    $timerFile = Join-Path $StateDir '_timer.json'

    if (Test-Path $timerFile) {
        try {
            $alt = Get-Content $timerFile -Raw | ConvertFrom-Json
            $p   = Get-Process -Id $alt.pid -ErrorAction Stop
            if ($p.StartTime.ToUniversalTime().Ticks -eq [int64] $alt.start) {
                Stop-Process -Id $alt.pid -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    $warte = $FertigMinuten * 60 + 2
    $p = Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
            -ArgumentList @('-NoProfile', '-File', "`"$PSCommandPath`"",
                            '-Event', 'Tick', '-WarteSekunden', $warte, '-BaseUrl', $BaseUrl,
                            '-FertigMinuten', $FertigMinuten, '-StaleMinutes', $StaleMinutes)
    @{ pid = $p.Id; start = $p.StartTime.ToUniversalTime().Ticks } |
        ConvertTo-Json -Compress | Set-Content -Path $timerFile -Encoding utf8
}

# Baut einen Lampenzustand aus einem Eintrag der Anzeigetabelle.
#
# Die Felder werden auch fuer ausgeschaltete Lampen gefuellt: die Firmware
# merkt sich Effekt und Helligkeit ueber das Ausschalten hinweg, und im
# Web-Interface steht dann nicht ueberall 100 % / steady, sobald man eine
# Lampe von Hand einschaltet.
function New-Lampe {
    param([hashtable] $Vorgabe, [bool] $An)

    return [ordered]@{
        on         = $An
        effect     = $(if ($Vorgabe.effect) { $Vorgabe.effect } else { 'steady' })
        brightness = [int]    $(if ($null -ne $Vorgabe.brightness) { $Vorgabe.brightness } else { 100 })
        frequency  = [double] $(if ($null -ne $Vorgabe.frequency)  { $Vorgabe.frequency }  else { 1.0 })
        duty       = [int]    $(if ($null -ne $Vorgabe.duty)       { $Vorgabe.duty }       else { 50 })
    }
}

# Welcher der Zustaende brennt gerade? Liefert den Schluesselnamen aus
# $Anzeige oder $null, wenn gar keine Session offen ist.
function Get-Hauptzustand {
    $jetzt        = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $grenze       = $jetzt - ($StaleMinutes  * 60)
    $fertigGrenze = $jetzt - ($FertigMinuten * 60)
    $sessions     = @()

    foreach ($f in (Get-ChildItem -Path $StateDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '_*') { continue }        # Hilfsdateien ueberspringen
        try { $s = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if (-not $s -or $s.ts -lt $grenze) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue   # abgestuerzte Session
            continue
        }
        $sessions += $s
    }

    $offen    = $sessions.Count -gt 0
    $wartet   = @($sessions | Where-Object { $_.state -eq 'waiting' }).Count -gt 0
    $fragt    = @($sessions | Where-Object { $_.state -eq 'asking'  }).Count -gt 0
    $arbeitet = @($sessions | Where-Object { $_.state -eq 'working' }).Count -gt 0
    # Nur 'done' zaehlt als fertig, und nur solange es frisch ist. 'idle'
    # (frisch geoeffnete Session) faellt bewusst durch bis auf 'bereit'.
    # -gt, nicht -ge: sonst hiesse -FertigMinuten 0 nicht "nie gruen", sondern
    # "gruen, solange der Zeitstempel in dieselbe Sekunde faellt".
    $fertig   = @($sessions | Where-Object { $_.state -eq 'done' -and $_.ts -gt $fertigGrenze }).Count -gt 0
    $fehler   = @($sessions | Where-Object { $_.error }).Count -gt 0

    $haupt = if     ($wartet)   { 'wartet'   }
             elseif ($fragt)    { 'fragt'    }
             elseif ($arbeitet) { 'arbeitet' }
             elseif ($fertig)   { 'fertig'   }
             elseif ($offen)    { 'bereit'   }
             else               { $null      }

    return [pscustomobject]@{ Haupt = $haupt; Fehler = $fehler }
}

# Vollstaendiger Sollzustand aller fuenf Lampen.
#
# Es werden immer alle fuenf beschrieben, nie nur die geaenderten. Das kostet
# nichts (ein einziger Request setzt alle) und repariert nebenbei jede
# Abweichung, die durch manuelles Schalten oder einen Neustart des ESP
# entstanden ist.
function Get-Lampen {
    $lage = Get-Hauptzustand

    $ziel = [ordered]@{}
    foreach ($name in $LAMPEN) { $ziel[$name] = New-Lampe -Vorgabe @{} -An $false }

    # Zwei Zustaende teilen sich Orange (fragt/wartet). Ein ausgeschalteter
    # Eintrag darf einen eingeschalteten derselben Lampe nicht ueberschreiben -
    # sonst entschiede die Reihenfolge der Tabelle, ob Orange ueberhaupt angeht.
    $gesetzt = @{}
    foreach ($zustand in $Anzeige.Keys) {
        $v  = $Anzeige[$zustand]
        $an = if ($zustand -eq 'fehler') { $lage.Fehler } else { $zustand -eq $lage.Haupt }
        if ($gesetzt[$v.lampe] -and -not $an) { continue }
        $ziel[$v.lampe] = New-Lampe -Vorgabe $v -An $an
        if ($an) { $gesetzt[$v.lampe] = $true }
    }

    return $ziel
}

# Ein Request fuer alle fuenf Lampen. Die Firmware uebernimmt sie atomar -
# entweder passt alles, oder es aendert sich nichts.
function Send-Lampen {
    param($Ziel)

    $json = ConvertTo-Json -InputObject $Ziel -Depth 4 -Compress
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/lamps" -Method Post -Body $json `
                          -ContentType 'application/json' -TimeoutSec 2 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Log "POST /api/lamps fehlgeschlagen: $($_.Exception.Message)"
        return $false
    }
}

function Update-Lampen { Send-Lampen -Ziel (Get-Lampen) }

# ---------------------------------------------------------------------------
#  Hauptlauf
# ---------------------------------------------------------------------------
try {
    if (-not (Test-Path $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }

    # Der Nachzuegler wartet VOR dem Mutex - sonst saesse er fuenf Minuten
    # darauf und blockierte jeden anderen Hook.
    if ($Event -eq 'Tick' -and $WarteSekunden -gt 0) { Start-Sleep -Seconds $WarteSekunden }

    # PostToolUse feuert nach jedem Werkzeugaufruf, also sehr oft. In aller
    # Regel wartet die Session dabei nicht, und dann gibt es nichts zu tun -
    # ohne Mutex und ohne Anfrage an die Saeule sofort wieder raus.
    if ($Event -eq 'ToolDone') {
        $hook = Read-HookInput
        $sid  = Resolve-SessionId -HookInput $hook
        if ((Get-SessionState -Id $sid) -notin @('waiting', 'asking')) { exit 0 }
    }

    # Alle Schreibzugriffe und HTTP-Aufrufe serialisieren: mehrere Sessions
    # koennen gleichzeitig feuern, und zwei parallele Laeufe wuerden sich
    # ueberholen - dann kaeme womoeglich der aeltere Stand zuletzt an.
    $mutex    = New-Object System.Threading.Mutex($false, 'Global\ClaudeStacklight')
    $gehalten = $false
    try { $gehalten = $mutex.WaitOne(3000) } catch [System.Threading.AbandonedMutexException] { $gehalten = $true }

    if ($Event -ne 'ToolDone') {
        $hook = Read-HookInput
        $sid  = Resolve-SessionId -HookInput $hook
    }

    switch ($Event) {
        # 'idle', nicht 'done': eine frisch geoeffnete Session ist bereit,
        # aber nichts ist fertig geworden - sonst gruent die Saeule beim
        # blossen Oeffnen eines Terminals.
        'SessionStart'     { Set-SessionState -Id $sid -State 'idle'    -ErrorFlag $false }
        # Ein neuer Prompt quittiert einen alten Fehler - sonst bliebe Rot ewig.
        'UserPromptSubmit' { Set-SessionState -Id $sid -State 'working' -ErrorFlag $false }
        # Unterschieden wird ueber getrennte Hook-Eintraege in settings.json
        # (Matcher auf den Notification-Typ bzw. den Werkzeugnamen), nicht ueber
        # Felder der Hook-Eingabe - deren Aufbau ist fuer Notification nicht
        # dokumentiert.
        'Freigabe'         { Set-SessionState -Id $sid -State 'waiting' }
        'Rueckfrage'       { Set-SessionState -Id $sid -State 'asking' }
        # Das Werkzeug ist gelaufen (freigegeben bzw. Frage beantwortet) -
        # Claude arbeitet weiter.
        'ToolDone'         { Set-SessionState -Id $sid -State 'working' }
        'Stop'             { Set-SessionState -Id $sid -State 'done';   Start-FertigTimer }
        'StopFailure'      { Set-SessionState -Id $sid -State 'done'    -ErrorFlag $true; Start-FertigTimer }
        'ToolFailure'      { Set-SessionState -Id $sid -ErrorFlag $true }
        'SessionEnd'       { Remove-SessionState -Id $sid }
        'AllOff'           { Get-ChildItem $StateDir -Filter '*.json' -File -EA SilentlyContinue |
                                Remove-Item -Force -EA SilentlyContinue }
    }

    switch ($Event) {
        'Status' {
            $lage = Get-Hauptzustand
            $ziel = Get-Lampen

            'Zustand : {0}{1}' -f $(if ($lage.Haupt) { $lage.Haupt } else { 'keine Session offen' }),
                                  $(if ($lage.Fehler) { ' + Fehler' } else { '' }) | Write-Output
            'Saeule  : {0}' -f $BaseUrl | Write-Output
            '' | Write-Output

            foreach ($name in $LAMPEN) {
                $l = $ziel[$name]
                if ($l.on) {
                    $wie = switch ($l.effect) {
                        'blink' { 'blinkt {0:0.#} Hz, {1} % Tastgrad' -f $l.frequency, $l.duty }
                        'pulse' { 'pulsiert {0:0.#} Hz'                -f $l.frequency }
                        default { 'dauerhaft' }
                    }
                    '{0,-7} AN  {1,3} %  {2}' -f $name, $l.brightness, $wie | Write-Output
                } else {
                    '{0,-7} --' -f $name | Write-Output
                }
            }

            # Ehrlich bleiben: gruen faellt nur dank des Nachzueglers von
            # selbst auf weiss. Laeuft keiner (Rechner war im Ruhezustand,
            # Prozess abgeschossen), wechselt es erst beim naechsten Ereignis.
            if ($lage.Haupt -eq 'fertig') {
                $laeuft = $false
                try {
                    $t = Get-Content (Join-Path $StateDir '_timer.json') -Raw | ConvertFrom-Json
                    $laeuft = (Get-Process -Id $t.pid -EA Stop).StartTime.ToUniversalTime().Ticks -eq [int64] $t.start
                } catch { }
                '' | Write-Output
                if ($laeuft) { 'Hinweis : Nachzuegler laeuft, gruen wechselt von selbst auf weiss.' | Write-Output }
                else         { 'Hinweis : kein Nachzuegler, gruen wechselt erst beim naechsten Ereignis.' | Write-Output }
            }
        }

        'SelfTest' {
            # Den Kanal-Durchlauf macht die Firmware selbst und stellt danach
            # den vorherigen Zustand wieder her. Solange er laeuft, waere ein
            # eigener Sollzustand verloren - deshalb abwarten und erst danach
            # neu setzen.
            $wartezeit = 6.0
            try {
                $a = Invoke-RestMethod -Uri "$BaseUrl/api/sweep" -TimeoutSec 2 -ErrorAction Stop
                if ($a.channels -and $a.holdMs) { $wartezeit = ($a.channels * $a.holdMs / 1000.0) + 0.5 }
            } catch {
                Write-Log "GET /api/sweep fehlgeschlagen: $($_.Exception.Message)"
                $wartezeit = 0
            }
            if ($wartezeit -gt 0) { Start-Sleep -Seconds $wartezeit }
            Send-Lampen -Ziel (Get-Lampen) | Out-Null
        }

        # Roter Warnblitz bei einem gefaehrlichen Kommando. Schnelles Blinken
        # statt Dauerlicht, damit er sich vom gerasteten Fehler-Rot
        # unterscheidet, und ueber den Hauptzustand gelegt statt an seine
        # Stelle - blau pulsiert waehrenddessen weiter.
        #
        # "Vorher" ist er nur bedingt: der PreToolUse-Hook feuert zwar vor der
        # Ausfuehrung, laeuft aber mit async=true, und allein der Start von
        # pwsh.exe kostet rund 300 ms (gemessen). Der Blitz liegt also faktisch
        # parallel zum Kommando. Zum rechtzeitigen Hochgucken reicht das nur,
        # solange noch eine Freigabe aussteht - bei einem bereits freigegebenen
        # Befehl siehst du ihn, waehrend er schon laeuft.
        'Danger' {
            if (-not (Test-Gefaehrlich -HookInput $hook)) { break }
            $blitz = Get-Lampen
            $blitz['red'] = New-Lampe -An $true `
                -Vorgabe @{ effect = 'blink'; brightness = 100; frequency = 6.0; duty = 50 }
            Send-Lampen -Ziel $blitz | Out-Null
            Start-Sleep -Seconds $FlashSeconds
            Send-Lampen -Ziel (Get-Lampen) | Out-Null
        }

        default {
            $ok = Send-Lampen -Ziel (Get-Lampen)
            if (-not $Quiet) { Write-Verbose ("Lampen gesetzt: " + $ok) }
        }
    }
}
catch {
    Write-Log "unerwarteter Fehler bei Event=$Event : $_"
}
finally {
    if ($gehalten -and $mutex) { try { $mutex.ReleaseMutex() } catch { } }
    if ($mutex) { $mutex.Dispose() }
}

exit 0
