# StatusStackLight – Claude Code session display

`stacklight.ps1` shows on the stack light what the running
[Claude Code](https://claude.com/claude-code) sessions are doing right now: whether Claude
is working, is done, has a question or is waiting for an approval. The script hooks into
Claude Code and drives the stack light through the [firmware's HTTP API](../firmware/API.md) –
or, in [relay mode](#relay-mode), through a relay server the stack light polls.

## What the stack light shows

| Lamp | State | Appearance |
|---|---|---|
| white | ready – session open, nothing going on | breathes very slowly, 0.15 Hz, up to 30 % |
| green | done – just finished | steady, 45 %, for five minutes |
| blue | working | pulsing, 0.3 Hz, 70 % |
| orange | a question for you | steady, 40 % |
| orange | waiting for an approval | blinking, 1.2 Hz, 40 % |
| red | error | steady, 100 %, latched until the next prompt |
| red | dangerous command (`rm -rf`, `git push --force`, …) | short flash, 6 Hz, on top of the other state |

Exactly one of ready/done/working/question/approval is lit (priority from right to left);
red sits on top independently.

## Setup

**Requirements:** Windows with [PowerShell 7](https://github.com/PowerShell/PowerShell)
(`pwsh.exe`) and a stack light running the firmware from this repo on the same network.

1. **Address of the stack light.** The script talks to it at `http://statusstacklight`. If
   your network does not resolve that name, set the environment variable `STACKLIGHT_URL`,
   for example to `http://statusstacklight.local` or `http://192.168.178.72`.
2. **Add the hooks.** Copy the `hooks` block from [`hooks.example.json`](hooks.example.json)
   into `~/.claude/settings.json`. In every entry, replace the placeholder
   `C:\path\to\StatusStackLight\claude-code\stacklight.ps1` with the actual path, and if
   PowerShell 7 lives elsewhere, `command` as well.
3. **Try it out** without waiting for a hook:

   ```powershell
   $s = 'C:\path\to\StatusStackLight\claude-code\stacklight.ps1'
   & $s -Event Status      # shows what the stack light should show, without switching anything
   & $s -Event SelfTest    # the firmware's channel sweep, then back to the actual state
   & $s -Event AllOff
   ```

The script keeps its state under `~/.claude/stacklight/` (one file per session, plus
`_timer.json` and `_error.log`). It always exits with exit code 0 – an unreachable stack
light never holds up Claude Code; errors end up in `_error.log`.

## Relay mode

Without a relay, computer and stack light must be on the same network. With the
[relay](../relay/README.md), a small server anywhere on the internet, they need not: the script
reports its events there, and the stack light fetches the result. Sessions on several
computers then show up on the same stack light.

Set two environment variables for the user that runs Claude Code, with a key of the role
*client* from the relay's admin interface, and restart Claude Code:

```powershell
setx STACKLIGHT_RELAY_URL "https://relay.example.org"
setx STACKLIGHT_RELAY_KEY "ssl_…"
```

The hooks stay exactly as they are. As soon as both variables are set, the script sends every
event as one `POST /api/v1/events` to the relay instead of switching the stack light itself;
without them it works in LAN mode as before. `-RelayUrl` and `-RelayKey` override the
variables, for example to try it out:

```powershell
& $s -Event Status -RelayUrl https://relay.example.org -RelayKey ssl_…
```

In relay mode, the appearance and the event rules are set in the relay's admin interface –
the `$Display` table in the script only applies to LAN mode. Two things stay local:

- **The dangerous-command check.** For `Danger` the script checks the command text itself and
  only reports `Danger` – the command never leaves the computer.
- **The `ToolDone` shortcut.** `PostToolUse` fires after every tool call; the script only
  reports it while the session is waiting or asking, the condition of the relay's default
  rule. For this it keeps its session files as before.

`SelfTest` talks to the stack light directly and only works in LAN mode. `AllOff` makes the
relay forget all sessions, including those of other computers.

## How it works

The hooks deliver **events**, the stack light shows a **state**. Every session stores its
state as a file under `~/.claude/stacklight/`; from these the script computes what the lamps
show and sets it in **one** `POST /api/lamps` – completely on every event, even if nothing
has changed. That way the next hook heals any deviation, whether caused by a restart of the
stack light, the web interface or curl. Several parallel sessions therefore do not switch
each other off, and a crashed session is forgotten after an hour without events.

| Hook | Matcher | Event in the script |
|---|---|---|
| `SessionStart` | – | `SessionStart` |
| `UserPromptSubmit` | – | `UserPromptSubmit` |
| `Notification` | `permission_prompt` | `Approval` |
| `Notification` | `elicitation_dialog\|elicitation_url_dialog\|agent_needs_input` | `Question` |
| `PreToolUse` | `ExitPlanMode` | `Approval` |
| `PreToolUse` | `AskUserQuestion` | `Question` |
| `PreToolUse` | `Bash`, with `if` on dangerous commands | `Danger` |
| `PostToolUse` | `*` | `ToolDone` |
| `Stop` / `StopFailure` | – | `Stop` / `StopFailure` |
| `SessionEnd` | – | `SessionEnd` |

The script still accepts `Freigabe` and `Rueckfrage`, the former German names of `Approval`
and `Question`, so older hook configurations keep working.

**Red only when it matters.** `PostToolUseFailure` is deliberately not wired up, although the
script understands it as `-Event ToolFailure`. Failed tool calls are part of normal work – a
search without a match, a test that is meant to fail – and Claude usually handles them by
itself. Red for each of them would come so often that you stop looking, and then it is
overlooked in the one case that counts. Red stays reserved for a response that ended in an
error (`StopFailure`) and for the warning flash.

**Orange only when Claude needs you.** The Notification hook has matchers on the
notification type: `permission_prompt` is an approval (blinking), `elicitation_dialog`,
`elicitation_url_dialog` and `agent_needs_input` are questions (steady). The idle notice
after a minute without input (`idle_prompt`) is deliberately left out – it would turn every
green into orange after 60 s. In addition, the tools `ExitPlanMode` (approval) and
`AskUserQuestion` (question) trigger directly via `PreToolUse`. The distinction is made
through separate hook entries with the events `Approval` and `Question`, not through fields
of the hook input: their structure is not documented for Notification.

A question that Claude simply asks as text at the end of its response cannot be detected by
the hooks – then the stack light shows green, as for every finished response.

**Orange goes off again** as soon as the approved tool has run or the question has been
answered: `PostToolUse` calls the script with `ToolDone`, and it switches back to blue.
Without that, orange would stay lit until the end of the response, because an approval is
not a new prompt. Limitation: Claude Code does not report a moment of "approval granted" –
during a long build it therefore blinks until the approved command has finished.
`PostToolUse` fires after every tool call; if the session is not waiting, the script exits
immediately without a request to the stack light.

**Green falls back to white after five minutes** – "freshly done" is different information
from "has been sitting there a while". Since no hook may fire for a long time after that,
`Stop` starts a hidden straggler that waits out the time and recomputes once. Only one ever
runs; a new `Stop` ends the previous one.

**Brightness:** White is by far the brightest lamp and needs much less percent to look
equally bright – undimmed it is unbearable as a steady light. When breathing, the percentage
is the peak: the breath runs from 0 up to there, and due to gamma correction the lower third
is practically dark. That is why the peak at 30 % is well above what white would need as a
steady light. Orange at full brightness is glaring up close and therefore runs dimmed; the
attention comes from the blinking, not from the brightness. All values are in the
`$Display` table at the top of the script.

**Warning flash only for real matches.** The `if` conditions in the `PreToolUse` hook
(`Bash(rm -rf *)` etc.) are only a rough pre-filter: commands that Claude Code cannot parse
cleanly – loops, `$(…)`, heredocs – are let through to be safe; even
`for i in 1; do echo "$(echo harmless)"; done` passes the pre-filter. The script therefore
checks the actual command text once more itself.
