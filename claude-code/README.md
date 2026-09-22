# StatusStackLight – Anzeige der Claude-Code-Sessions

`stacklight.ps1` zeigt auf der Säule, was die laufenden
[Claude-Code](https://claude.com/claude-code)-Sessions gerade tun: ob Claude arbeitet, fertig
ist, eine Rückfrage hat oder auf eine Freigabe wartet. Das Skript hängt über Hooks in Claude
Code und steuert die Säule über die [HTTP-API der Firmware](../firmware/API.md).

## Was die Säule zeigt

| Lampe | Zustand | Darstellung |
|---|---|---|
| weiß | bereit – Session offen, nichts los | atmet sehr langsam, 0,15 Hz, bis 30 % |
| grün | fertig – gerade fertig geworden | dauerhaft, 45 %, fünf Minuten lang |
| blau | arbeitet | pulsierend, 0,3 Hz, 70 % |
| orange | Rückfrage an dich | dauerhaft, 40 % |
| orange | wartet auf eine Freigabe | blinkend, 1,2 Hz, 50 % |
| rot | Fehler | dauerhaft, 100 %, rastet bis zum nächsten Prompt |
| rot | gefährlicher Befehl (`rm -rf`, `git push --force`, …) | kurzer Blitz, 6 Hz, über dem übrigen Zustand |

Genau eine von bereit/fertig/arbeitet/Rückfrage/Freigabe brennt (Rangfolge von rechts nach
links), rot liegt unabhängig darüber.

## Einrichten

**Voraussetzungen:** Windows mit [PowerShell 7](https://github.com/PowerShell/PowerShell)
(`pwsh.exe`) und eine Säule mit der Firmware aus diesem Repo im selben Netz.

1. **Adresse der Säule.** Das Skript spricht sie unter `http://statusstacklight` an. Löst
   dein Netz diesen Namen nicht auf, die Umgebungsvariable `STACKLIGHT_URL` setzen, etwa auf
   `http://statusstacklight.local` oder `http://192.168.178.72`.
2. **Hooks eintragen.** Den Block `hooks` aus [`hooks.example.json`](hooks.example.json) in
   `~/.claude/settings.json` übernehmen. In allen Einträgen den Platzhalter
   `C:\Pfad\zu\StatusStackLight\claude-code\stacklight.ps1` durch den tatsächlichen Pfad
   ersetzen, und falls PowerShell 7 woanders liegt, auch `command`.
3. **Ausprobieren**, ohne auf einen Hook zu warten:

   ```powershell
   $s = 'C:\Pfad\zu\StatusStackLight\claude-code\stacklight.ps1'
   & $s -Event Status      # zeigt, was die Säule zeigen sollte, ohne etwas zu schalten
   & $s -Event SelfTest    # Kanal-Durchlauf der Firmware, danach zurück in den Istzustand
   & $s -Event AllOff
   ```

Das Skript legt seinen Zustand unter `~/.claude/stacklight/` ab (eine Datei je Session, dazu
`_timer.json` und `_error.log`). Es beendet sich immer mit Exit-Code 0 – eine
nicht erreichbare Säule hält Claude Code nie auf; Fehler landen in `_error.log`.

## Wie es funktioniert

Die Hooks liefern **Ereignisse**, die Säule zeigt einen **Zustand**. Jede Session legt ihren
Zustand als Datei unter `~/.claude/stacklight/` ab; daraus wird berechnet, was die Lampen
zeigen, und in **einem** `POST /api/lamps` gesetzt – bei jedem Ereignis vollständig, auch
wenn sich nichts geändert hat. So heilt der nächste Hook jede Abweichung, ob durch Neustart
der Säule, Web-Interface oder curl. Mehrere parallele Sessions knipsen sich dadurch nicht
gegenseitig aus, und eine abgestürzte Session wird nach einer Stunde ohne Ereignis vergessen.

| Hook | Matcher | Event im Skript |
|---|---|---|
| `SessionStart` | – | `SessionStart` |
| `UserPromptSubmit` | – | `UserPromptSubmit` |
| `Notification` | `permission_prompt` | `Freigabe` |
| `Notification` | `elicitation_dialog\|elicitation_url_dialog\|agent_needs_input` | `Rueckfrage` |
| `PreToolUse` | `ExitPlanMode` | `Freigabe` |
| `PreToolUse` | `AskUserQuestion` | `Rueckfrage` |
| `PreToolUse` | `Bash`, mit `if` auf gefährliche Befehle | `Danger` |
| `PostToolUse` | `*` | `ToolDone` |
| `Stop` / `StopFailure` | – | `Stop` / `StopFailure` |
| `SessionEnd` | – | `SessionEnd` |

**Orange nur, wenn Claude dich braucht.** Der Notification-Hook hat Matcher auf den
Benachrichtigungstyp: `permission_prompt` ist eine Freigabe (blinkt),
`elicitation_dialog`, `elicitation_url_dialog` und `agent_needs_input` sind Rückfragen
(ruhig). Die Leerlauf-Meldung nach einer Minute ohne Eingabe (`idle_prompt`) ist bewusst
nicht dabei – sie würde jedes Grün nach 60 s zu Orange machen. Zusätzlich lösen die
Werkzeuge `ExitPlanMode` (Freigabe) und `AskUserQuestion` (Rückfrage) über `PreToolUse`
direkt aus. Getrennt wird über eigene Hook-Einträge mit den Events `Freigabe` und
`Rueckfrage`, nicht über Felder der Hook-Eingabe: deren Aufbau ist für Notification nicht
dokumentiert.

Eine Frage, die Claude einfach als Text am Ende seiner Antwort stellt, ist für die Hooks
nicht erkennbar – dann zeigt die Säule grün, wie bei jeder fertigen Antwort.

**Orange geht wieder aus**, sobald das freigegebene Werkzeug gelaufen bzw. die Frage
beantwortet ist: `PostToolUse` ruft das Skript mit `ToolDone` auf, und es springt zurück
auf blau. Ohne das bliebe Orange bis zum Ende der Antwort stehen, denn eine Freigabe ist
kein neuer Prompt. Grenze: Einen Zeitpunkt „Freigabe erteilt" meldet Claude Code nicht –
bei einem langen Build blinkt es also, bis der freigegebene Befehl fertig ist.
`PostToolUse` feuert nach jedem Werkzeugaufruf; wartet die Session nicht, beendet sich das
Skript sofort ohne Anfrage an die Säule.

**Grün fällt nach fünf Minuten auf weiß** – „frisch fertig" ist eine andere Information
als „steht schon eine Weile da". Weil danach womöglich lange kein Hook mehr feuert, startet
`Stop` einen versteckten Nachzügler, der die Zeit absitzt und einmal neu rechnet. Es läuft
immer nur einer; ein neuer `Stop` beendet den vorigen.

**Helligkeiten:** Weiß ist mit Abstand die hellste Lampe und braucht viel weniger Prozent,
um gleich hell zu wirken – ungedimmt ist es als Dauerlicht nicht zu ertragen. Beim Atmen ist
die Prozentzahl der Gipfel: der Atemzug läuft von 0 bis dorthin, und durch die
Gammakorrektur ist das untere Drittel praktisch dunkel. Deshalb liegt der Gipfel mit 30 %
deutlich über dem, was Weiß als Dauerlicht bräuchte. Orange ist mit voller Helligkeit aus
der Nähe grell und läuft deshalb gedimmt; die Aufmerksamkeit kommt vom Blinken, nicht von
der Helligkeit. Alle Werte stehen in der Tabelle `$Anzeige` oben im Skript.

**Warnblitz nur bei echten Treffern.** Die `if`-Bedingungen im `PreToolUse`-Hook
(`Bash(rm -rf *)` usw.) sind nur ein grober Vorfilter: Befehle, die Claude Code nicht sauber
zerlegen kann – Schleifen, `$(…)`, Heredocs –, lässt es sicherheitshalber durch; schon
`for i in 1; do echo "$(echo harmlos)"; done` passiert den Vorfilter. Das Skript prüft
deshalb den tatsächlichen Befehlstext noch einmal selbst.
