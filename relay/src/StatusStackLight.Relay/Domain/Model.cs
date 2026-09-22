namespace StatusStackLight.Relay.Domain;

/// <summary>The five lamps, in channel order 1...5 as on the firmware.</summary>
public enum LampId { White, Blue, Green, Orange, Red }

/// <summary>Lamp effect, named as in the firmware API.</summary>
public enum Effect { Steady, Blink, Pulse }

/// <summary>What a single Claude Code session is doing right now.</summary>
public enum SessionState { Idle, Working, Asking, Waiting, Done }

/// <summary>
/// The states the stack light can show. The first five are main states - exactly one of them
/// is lit. Error and Danger are overlays that sit on top independently.
/// </summary>
public enum DisplayState { Ready, Done, Working, Asking, Waiting, Error, Danger }

/// <summary>The events the hook script reports - one per hook entry in settings.json.</summary>
public enum HookEvent
{
    SessionStart, UserPromptSubmit, Approval, Question, ToolDone,
    Stop, StopFailure, ToolFailure, SessionEnd, Danger,
}

/// <summary>What an event does to the state of its session.</summary>
public enum StateAction { Keep, Idle, Working, Asking, Waiting, Done, End }

/// <summary>What an event does to the error flag of its session.</summary>
public enum ErrorAction { Keep, Set, Clear }

/// <summary>How one lamp looks while a display state is active.</summary>
public sealed record LampSetting(
    LampId Lamp,
    Effect Effect = Effect.Steady,
    int Brightness = 100,
    double Frequency = 1.0,
    int Duty = 50);

/// <summary>
/// Target state of one lamp, exactly the fields the firmware accepts in POST /api/lamps.
/// </summary>
public sealed record LampOutput(bool On, Effect Effect, int Brightness, double Frequency, int Duty)
{
    public static LampOutput From(LampSetting s, bool on) =>
        new(on, s.Effect, s.Brightness, s.Frequency, s.Duty);

    /// <summary>A lamp that no display state claims: off, with the firmware defaults.</summary>
    public static readonly LampOutput Unused = new(false, Effect.Steady, 100, 1.0, 50);
}

/// <summary>What happens when an event arrives.</summary>
public sealed record EventRule
{
    public StateAction State { get; init; } = StateAction.Keep;
    public ErrorAction Error { get; init; } = ErrorAction.Keep;

    /// <summary>Empty: always. Otherwise the event is ignored unless the session is in one of these.</summary>
    public IReadOnlyList<SessionState> OnlyWhen { get; init; } = [];

    /// <summary>Lays the danger display over everything for FlashSeconds.</summary>
    public bool Flash { get; init; }

    /// <summary>An event that neither changes the state nor the error does not touch the session.</summary>
    public bool TouchesSession => State != StateAction.Keep || Error != ErrorAction.Keep;
}

/// <summary>Timings and the priority of the main states.</summary>
public sealed record RelaySettings
{
    /// <summary>Main states from highest to lowest priority. Must contain each main state once.</summary>
    public IReadOnlyList<DisplayState> Priority { get; init; } = [];

    /// <summary>For this long after finishing, Done shows; then it falls back to Ready.</summary>
    public double DoneMinutes { get; init; }

    /// <summary>A session without an event for this long counts as crashed and is forgotten.</summary>
    public double StaleMinutes { get; init; }

    /// <summary>Duration of the warning flash.</summary>
    public double FlashSeconds { get; init; }

    /// <summary>Longest time a lamp's poll is held open without a change.</summary>
    public int LongPollSeconds { get; init; }
}

/// <summary>Everything the admin can configure, as one immutable snapshot.</summary>
public sealed record RelayConfig(
    IReadOnlyDictionary<DisplayState, IReadOnlyList<LampSetting>> Appearance,
    IReadOnlyDictionary<HookEvent, EventRule> Rules,
    RelaySettings Settings);

public static class DisplayStates
{
    public static readonly IReadOnlyList<DisplayState> Main =
        [DisplayState.Ready, DisplayState.Done, DisplayState.Working, DisplayState.Asking, DisplayState.Waiting];

    public static bool IsMain(DisplayState s) => s <= DisplayState.Waiting;
}
