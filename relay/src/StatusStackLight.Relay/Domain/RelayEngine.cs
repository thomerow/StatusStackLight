namespace StatusStackLight.Relay.Domain;

/// <summary>The image the lamps should show, with the version it carries.</summary>
public sealed record DisplaySnapshot(
    long Version,
    Situation Situation,
    IReadOnlyDictionary<LampId, LampOutput> Lamps);

/// <summary>
/// The heart of the relay: keeps the sessions, applies events according to the rules and keeps
/// the resulting lamp image up to date.
///
/// The version only goes up when the image really changes. A lamp that polls with the version
/// it already shows therefore waits until there is something new, and a burst of events that
/// ends where it started (ToolDone after ToolDone) costs it nothing.
///
/// Sessions live in memory only: after a restart of the relay the next hook of every session
/// brings its state back, and a session without events is forgotten after StaleMinutes anyway.
/// </summary>
public sealed class RelayEngine
{
    private readonly TimeProvider _time;
    private readonly Lock _lock = new();
    private readonly Dictionary<string, Session> _sessions = new(StringComparer.Ordinal);

    private RelayConfig _config;
    private DateTimeOffset _flashUntil = DateTimeOffset.MinValue;
    private DisplaySnapshot _snapshot;
    private TaskCompletionSource _changed = NewSignal();

    public RelayEngine(RelayConfig config, TimeProvider time)
    {
        _config = config;
        _time   = time;

        // Not 1: after a restart of the relay, a lamp polls with the version from before. With
        // a start value from the clock, the new count cannot collide with it by chance - any
        // difference makes the lamp fetch the image.
        long start = time.GetUtcNow().ToUnixTimeSeconds();
        var situation = new Situation(null, false, false);
        _snapshot = new DisplaySnapshot(start, situation, DisplayComposer.Compose(situation, config.Appearance));
    }

    public RelayConfig Config { get { lock (_lock) return _config; } }

    public DisplaySnapshot Snapshot { get { lock (_lock) return _snapshot; } }

    public IReadOnlyList<Session> Sessions
    {
        get { lock (_lock) return [.. _sessions.Values.OrderBy(s => s.LastEvent)]; }
    }

    /// <summary>Applies an event. Returns false if the rule's condition made it a no-op.</summary>
    public bool Apply(HookEvent ev, string sessionId, string? host)
    {
        lock (_lock) {
            var now  = _time.GetUtcNow();
            var rule = _config.Rules.TryGetValue(ev, out var r) ? r : new EventRule();
            _sessions.TryGetValue(sessionId, out var current);

            if (rule.OnlyWhen.Count > 0 && (current is null || !rule.OnlyWhen.Contains(current.State))) {
                return false;
            }

            if (rule.State == StateAction.End) {
                _sessions.Remove(sessionId);
            } else if (rule.TouchesSession) {
                // A session the relay does not know yet (relay restarted, or the hook of its
                // start got lost) starts out idle, as in the script.
                var state = rule.State switch
                {
                    StateAction.Idle    => SessionState.Idle,
                    StateAction.Working => SessionState.Working,
                    StateAction.Asking  => SessionState.Asking,
                    StateAction.Waiting => SessionState.Waiting,
                    StateAction.Done    => SessionState.Done,
                    _                   => current?.State ?? SessionState.Idle,
                };
                bool error = rule.Error switch
                {
                    ErrorAction.Set   => true,
                    ErrorAction.Clear => false,
                    _                 => current?.Error ?? false,
                };
                _sessions[sessionId] = new Session(sessionId, host ?? current?.Host, state, error, now);
            }

            if (rule.Flash) {
                _flashUntil = now + TimeSpan.FromSeconds(_config.Settings.FlashSeconds);
            }

            RecomputeLocked(now);
            return true;
        }
    }

    /// <summary>Forgets all sessions - the stack light goes dark.</summary>
    public void Clear()
    {
        lock (_lock) {
            _sessions.Clear();
            _flashUntil = DateTimeOffset.MinValue;
            RecomputeLocked(_time.GetUtcNow());
        }
    }

    /// <summary>Takes over a new configuration and shows its effect right away.</summary>
    public void UpdateConfig(RelayConfig config)
    {
        lock (_lock) {
            _config = config;
            RecomputeLocked(_time.GetUtcNow());
        }
    }

    /// <summary>
    /// Time-driven transitions: Done falls back to Ready, crashed sessions are forgotten, the
    /// warning flash ends. Called periodically by the timer service.
    /// </summary>
    public void Tick()
    {
        lock (_lock) RecomputeLocked(_time.GetUtcNow());
    }

    /// <summary>
    /// Returns as soon as the version differs from <paramref name="knownVersion"/>, at the
    /// latest after <paramref name="timeout"/> with the unchanged image.
    /// </summary>
    public async Task<DisplaySnapshot> WaitForChangeAsync(long knownVersion, TimeSpan timeout,
                                                          CancellationToken cancel)
    {
        Task signal;
        lock (_lock) {
            if (_snapshot.Version != knownVersion || timeout <= TimeSpan.Zero) return _snapshot;
            signal = _changed.Task;
        }

        try {
            await signal.WaitAsync(timeout, _time, cancel);
        } catch (TimeoutException) {
        }
        return Snapshot;
    }

    private void RecomputeLocked(DateTimeOffset now)
    {
        var staleEdge = now - TimeSpan.FromMinutes(_config.Settings.StaleMinutes);
        foreach (var s in _sessions.Values.Where(s => s.LastEvent < staleEdge).ToList()) {
            _sessions.Remove(s.Id);
        }

        var situation = DisplayComposer.Evaluate(_sessions.Values, _config.Settings, now, now < _flashUntil);
        var lamps     = DisplayComposer.Compose(situation, _config.Appearance);

        bool changed = situation != _snapshot.Situation
                    || lamps.Any(kv => _snapshot.Lamps[kv.Key] != kv.Value);
        if (!changed) return;

        _snapshot = new DisplaySnapshot(_snapshot.Version + 1, situation, lamps);
        var signal = _changed;
        _changed = NewSignal();
        signal.SetResult();
    }

    private static TaskCompletionSource NewSignal() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);
}
