namespace StatusStackLight.Relay.Domain;

/// <summary>A session as the relay keeps it.</summary>
public sealed record Session(string Id, string? Host, SessionState State, bool Error, DateTimeOffset LastEvent);

/// <summary>What the stack light shows, before it becomes lamp states.</summary>
public sealed record Situation(DisplayState? Main, bool Error, bool Flash);

/// <summary>
/// Turns sessions into the image of the five lamps. Pure functions, port of Get-MainState and
/// Get-Lamps from claude-code/stacklight.ps1.
/// </summary>
public static class DisplayComposer
{
    /// <summary>
    /// Which main state is lit, and whether the error overlay is. Main is null if no session
    /// is open. Stale sessions must already have been removed.
    /// </summary>
    public static Situation Evaluate(IEnumerable<Session> sessions, RelaySettings settings,
                                     DateTimeOffset now, bool flash)
    {
        var list     = sessions as IReadOnlyCollection<Session> ?? sessions.ToList();
        var doneEdge = now - TimeSpan.FromMinutes(settings.DoneMinutes);

        bool Active(DisplayState state) => state switch
        {
            DisplayState.Waiting => list.Any(s => s.State == SessionState.Waiting),
            DisplayState.Asking  => list.Any(s => s.State == SessionState.Asking),
            DisplayState.Working => list.Any(s => s.State == SessionState.Working),
            // Only Done counts as done, and only while it is fresh. Idle (freshly opened) falls
            // through to Ready. ">", not ">=": DoneMinutes 0 means "never green".
            DisplayState.Done    => list.Any(s => s.State == SessionState.Done && s.LastEvent > doneEdge),
            DisplayState.Ready   => list.Count > 0,
            _                    => false,
        };

        DisplayState? main = null;
        foreach (var state in settings.Priority) {
            if (Active(state)) { main = state; break; }
        }
        return new Situation(main, list.Any(s => s.Error), flash);
    }

    /// <summary>
    /// Complete target state of all five lamps. Lamps that are off still carry the parameters
    /// of their display state, so the stack light's web interface shows sensible values.
    /// </summary>
    public static IReadOnlyDictionary<LampId, LampOutput> Compose(
        Situation situation, IReadOnlyDictionary<DisplayState, IReadOnlyList<LampSetting>> appearance)
    {
        var target = Enum.GetValues<LampId>().ToDictionary(l => l, _ => LampOutput.Unused);

        // Several states can share a lamp (asking/waiting are both orange). An entry that is off
        // must not overwrite one of the same lamp that is on - otherwise the order would decide
        // whether the lamp comes on at all.
        var claimed = new HashSet<LampId>();
        foreach (var state in Enum.GetValues<DisplayState>()) {
            if (state == DisplayState.Danger) continue;
            if (!appearance.TryGetValue(state, out var settings)) continue;

            bool on = state == DisplayState.Error ? situation.Error : state == situation.Main;
            foreach (var s in settings) {
                if (claimed.Contains(s.Lamp) && !on) continue;
                target[s.Lamp] = LampOutput.From(s, on);
                if (on) claimed.Add(s.Lamp);
            }
        }

        // The warning flash sits on top of everything, but leaves the other lamps alone - blue
        // keeps pulsing while red flashes.
        if (situation.Flash && appearance.TryGetValue(DisplayState.Danger, out var flash)) {
            foreach (var s in flash) target[s.Lamp] = LampOutput.From(s, true);
        }

        return target;
    }
}
