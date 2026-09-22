namespace StatusStackLight.Relay.Domain;

/// <summary>
/// The factory settings - the one place where they are defined. Seeding a new database and
/// "reset to defaults" in the admin interface both use this.
///
/// They reproduce exactly what claude-code/stacklight.ps1 does in LAN mode; the comments there
/// explain why the stack light looks the way it does.
/// </summary>
public static class Defaults
{
    public static IReadOnlyDictionary<DisplayState, IReadOnlyList<LampSetting>> Appearance { get; } =
        new Dictionary<DisplayState, IReadOnlyList<LampSetting>>
        {
            // A session is open, nothing is happening: dim white, breathing very slowly.
            [DisplayState.Ready]   = [new(LampId.White,  Effect.Pulse,  30, 0.15)],
            // Freshly done: calm green, nothing to do, just something to read.
            [DisplayState.Done]    = [new(LampId.Green,  Effect.Steady, 45)],
            // Claude is working: slow blue pulse, motion without restlessness.
            [DisplayState.Working] = [new(LampId.Blue,   Effect.Pulse,  70, 0.3)],
            // A question: steady orange, so it differs from an approval at a glance.
            [DisplayState.Asking]  = [new(LampId.Orange, Effect.Steady, 40)],
            // Waiting for an approval - the important one: hard blinking.
            [DisplayState.Waiting] = [new(LampId.Orange, Effect.Blink,  40, 1.2, 55)],
            // Error: latched until the next prompt.
            [DisplayState.Error]   = [new(LampId.Red,    Effect.Steady, 100)],
            // Warning flash for a dangerous command.
            [DisplayState.Danger]  = [new(LampId.Red,    Effect.Blink,  100, 6.0, 50)],
        };

    public static IReadOnlyDictionary<HookEvent, EventRule> Rules { get; } =
        new Dictionary<HookEvent, EventRule>
        {
            // Idle, not Done: a freshly opened session has not finished anything.
            [HookEvent.SessionStart]     = new() { State = StateAction.Idle,    Error = ErrorAction.Clear },
            // A new prompt acknowledges an old error.
            [HookEvent.UserPromptSubmit] = new() { State = StateAction.Working, Error = ErrorAction.Clear },
            [HookEvent.Approval]         = new() { State = StateAction.Waiting },
            [HookEvent.Question]         = new() { State = StateAction.Asking },
            // Fires after every tool call; only matters when the session was waiting for you.
            [HookEvent.ToolDone]         = new() { State = StateAction.Working,
                                                   OnlyWhen = [SessionState.Waiting, SessionState.Asking] },
            [HookEvent.Stop]             = new() { State = StateAction.Done },
            [HookEvent.StopFailure]      = new() { State = StateAction.Done,    Error = ErrorAction.Set },
            [HookEvent.ToolFailure]      = new() { Error = ErrorAction.Set },
            [HookEvent.SessionEnd]       = new() { State = StateAction.End },
            [HookEvent.Danger]           = new() { Flash = true },
        };

    public static RelaySettings Settings { get; } = new()
    {
        Priority        = [DisplayState.Waiting, DisplayState.Asking, DisplayState.Working,
                           DisplayState.Done, DisplayState.Ready],
        DoneMinutes     = 5,
        StaleMinutes    = 60,
        FlashSeconds    = 1.2,
        LongPollSeconds = 25,
    };

    public static RelayConfig Config { get; } = new(Appearance, Rules, Settings);
}
