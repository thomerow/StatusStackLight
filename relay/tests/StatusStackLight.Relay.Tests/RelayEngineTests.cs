using Microsoft.Extensions.Time.Testing;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Tests;

public class RelayEngineTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 9, 22, 12, 0, 0, TimeSpan.Zero));
    private readonly RelayEngine _engine;

    public RelayEngineTests() => _engine = new RelayEngine(Defaults.Config, _time);

    private LampOutput Lamp(LampId id) => _engine.Snapshot.Lamps[id];
    private DisplayState? Main => _engine.Snapshot.Situation.Main;

    private static readonly LampId[] AllLamps = Enum.GetValues<LampId>();

    // Lit lamps only, for compact assertions.
    private LampId[] Lit => AllLamps.Where(l => Lamp(l).On).ToArray();

    [Fact]
    public void Without_sessions_everything_is_off()
    {
        Assert.Null(Main);
        Assert.Empty(Lit);
    }

    [Fact]
    public void Session_start_shows_ready_as_dim_breathing_white()
    {
        _engine.Apply(HookEvent.SessionStart, "a", "pc");

        Assert.Equal(DisplayState.Ready, Main);
        Assert.Equal([LampId.White], Lit);
        Assert.Equal(new LampOutput(true, Effect.Pulse, 30, 0.15, 50), Lamp(LampId.White));
    }

    [Fact]
    public void Prompt_shows_working_as_blue_pulse()
    {
        _engine.Apply(HookEvent.SessionStart, "a", null);
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);

        Assert.Equal(DisplayState.Working, Main);
        Assert.Equal([LampId.Blue], Lit);
        Assert.Equal(new LampOutput(true, Effect.Pulse, 70, 0.3, 50), Lamp(LampId.Blue));
    }

    [Fact]
    public void Approval_blinks_orange_and_question_keeps_it_steady()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        _engine.Apply(HookEvent.Approval, "a", null);
        Assert.Equal(new LampOutput(true, Effect.Blink, 40, 1.2, 55), Lamp(LampId.Orange));

        _engine.Apply(HookEvent.Question, "a", null);
        Assert.Equal(new LampOutput(true, Effect.Steady, 40, 1.0, 50), Lamp(LampId.Orange));
    }

    [Fact]
    public void Shared_lamp_is_not_switched_off_by_a_later_entry()
    {
        // asking comes before waiting in the iteration order, and both use orange. The entry of
        // waiting (off) must not overwrite the one of asking (on).
        _engine.Apply(HookEvent.Question, "a", null);

        Assert.Equal([LampId.Orange], Lit);
    }

    [Fact]
    public void Waiting_beats_asking_beats_working_beats_done_across_sessions()
    {
        _engine.Apply(HookEvent.Stop, "done", null);
        Assert.Equal(DisplayState.Done, Main);
        _engine.Apply(HookEvent.UserPromptSubmit, "working", null);
        Assert.Equal(DisplayState.Working, Main);
        _engine.Apply(HookEvent.Question, "asking", null);
        Assert.Equal(DisplayState.Asking, Main);
        _engine.Apply(HookEvent.Approval, "waiting", null);
        Assert.Equal(DisplayState.Waiting, Main);

        // Exactly one main state is lit.
        Assert.Equal([LampId.Orange], Lit);
        Assert.Equal(Effect.Blink, Lamp(LampId.Orange).Effect);
    }

    [Fact]
    public void Custom_priority_is_honoured()
    {
        var settings = Defaults.Settings with
        {
            Priority = [DisplayState.Working, DisplayState.Waiting, DisplayState.Asking,
                        DisplayState.Done, DisplayState.Ready],
        };
        _engine.UpdateConfig(Defaults.Config with { Settings = settings });

        _engine.Apply(HookEvent.Approval, "a", null);
        _engine.Apply(HookEvent.UserPromptSubmit, "b", null);

        Assert.Equal(DisplayState.Working, Main);
    }

    [Fact]
    public void Done_falls_back_to_ready_after_done_minutes()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        _engine.Apply(HookEvent.Stop, "a", null);
        Assert.Equal(DisplayState.Done, Main);
        Assert.Equal(new LampOutput(true, Effect.Steady, 45, 1.0, 50), Lamp(LampId.Green));

        _time.Advance(TimeSpan.FromMinutes(4.9));
        _engine.Tick();
        Assert.Equal(DisplayState.Done, Main);

        _time.Advance(TimeSpan.FromMinutes(0.2));
        _engine.Tick();
        Assert.Equal(DisplayState.Ready, Main);
        Assert.Equal([LampId.White], Lit);
    }

    [Fact]
    public void Stale_sessions_are_forgotten()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "crashed", null);
        _time.Advance(TimeSpan.FromMinutes(61));
        _engine.Tick();

        Assert.Empty(_engine.Sessions);
        Assert.Null(Main);
        Assert.Empty(Lit);
    }

    [Fact]
    public void Error_is_latched_until_the_next_prompt()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        _engine.Apply(HookEvent.ToolFailure, "a", null);
        Assert.Equal([LampId.Blue, LampId.Red], Lit);

        _engine.Apply(HookEvent.Stop, "a", null);
        Assert.Equal([LampId.Green, LampId.Red], Lit);

        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        Assert.Equal([LampId.Blue], Lit);
    }

    [Fact]
    public void Stop_failure_sets_done_and_error()
    {
        _engine.Apply(HookEvent.StopFailure, "a", null);

        Assert.Equal(DisplayState.Done, Main);
        Assert.True(_engine.Snapshot.Situation.Error);
        Assert.Equal(new LampOutput(true, Effect.Steady, 100, 1.0, 50), Lamp(LampId.Red));
    }

    [Fact]
    public void Tool_failure_of_an_unknown_session_creates_it_idle()
    {
        _engine.Apply(HookEvent.ToolFailure, "new", null);

        var s = Assert.Single(_engine.Sessions);
        Assert.Equal(SessionState.Idle, s.State);
        Assert.True(s.Error);
    }

    [Fact]
    public void Tool_done_only_acts_while_waiting_or_asking()
    {
        _engine.Apply(HookEvent.Stop, "a", null);
        Assert.False(_engine.Apply(HookEvent.ToolDone, "a", null));
        Assert.Equal(DisplayState.Done, Main);

        _engine.Apply(HookEvent.Approval, "a", null);
        Assert.True(_engine.Apply(HookEvent.ToolDone, "a", null));
        Assert.Equal(DisplayState.Working, Main);

        // Unknown session: ignored, not created.
        Assert.False(_engine.Apply(HookEvent.ToolDone, "unknown", null));
        Assert.Single(_engine.Sessions);
    }

    [Fact]
    public void Session_end_removes_the_session()
    {
        _engine.Apply(HookEvent.SessionStart, "a", null);
        _engine.Apply(HookEvent.SessionEnd, "a", null);

        Assert.Empty(_engine.Sessions);
        Assert.Empty(Lit);
    }

    [Fact]
    public void Danger_flashes_red_on_top_and_ends_by_itself()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        _engine.Apply(HookEvent.Danger, "a", null);

        Assert.Equal([LampId.Blue, LampId.Red], Lit);
        Assert.Equal(new LampOutput(true, Effect.Blink, 100, 6.0, 50), Lamp(LampId.Red));

        _time.Advance(TimeSpan.FromSeconds(1.3));
        _engine.Tick();
        Assert.Equal([LampId.Blue], Lit);
    }

    [Fact]
    public void Danger_does_not_touch_the_session()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        var before = _engine.Sessions.Single();
        _time.Advance(TimeSpan.FromSeconds(10));

        _engine.Apply(HookEvent.Danger, "a", null);

        Assert.Equal(before, _engine.Sessions.Single());
    }

    [Fact]
    public void Lamps_that_are_off_keep_the_parameters_of_their_state()
    {
        _engine.Apply(HookEvent.SessionStart, "a", null);

        Assert.Equal(new LampOutput(false, Effect.Pulse, 70, 0.3, 50), Lamp(LampId.Blue));
        Assert.Equal(new LampOutput(false, Effect.Blink, 40, 1.2, 55), Lamp(LampId.Orange));
    }

    [Fact]
    public void Version_only_changes_with_the_image()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        long v = _engine.Snapshot.Version;

        // Same image again: another session working, a second prompt.
        _engine.Apply(HookEvent.UserPromptSubmit, "b", null);
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        _engine.Tick();
        Assert.Equal(v, _engine.Snapshot.Version);

        _engine.Apply(HookEvent.Approval, "a", null);
        Assert.Equal(v + 1, _engine.Snapshot.Version);
    }

    [Fact]
    public void Clear_forgets_everything()
    {
        _engine.Apply(HookEvent.Approval, "a", null);
        _engine.Apply(HookEvent.ToolFailure, "b", null);
        _engine.Clear();

        Assert.Empty(_engine.Sessions);
        Assert.Empty(Lit);
    }

    [Fact]
    public void Config_change_shows_immediately()
    {
        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);
        long v = _engine.Snapshot.Version;

        var appearance = new Dictionary<DisplayState, IReadOnlyList<LampSetting>>(Defaults.Appearance)
        {
            [DisplayState.Working] = [new(LampId.Blue, Effect.Blink, 20, 2.0, 30), new(LampId.White)],
        };
        _engine.UpdateConfig(Defaults.Config with { Appearance = appearance });

        Assert.Equal(v + 1, _engine.Snapshot.Version);
        Assert.Equal([LampId.White, LampId.Blue], Lit);
    }

    [Fact]
    public async Task Wait_returns_at_once_when_the_version_differs()
    {
        var snap = await _engine.WaitForChangeAsync(0, TimeSpan.FromSeconds(25), CancellationToken.None);

        Assert.Equal(_engine.Snapshot.Version, snap.Version);
    }

    [Fact]
    public async Task Wait_returns_on_change()
    {
        long v = _engine.Snapshot.Version;
        var wait = _engine.WaitForChangeAsync(v, TimeSpan.FromSeconds(25), CancellationToken.None);
        Assert.False(wait.IsCompleted);

        _engine.Apply(HookEvent.UserPromptSubmit, "a", null);

        var snap = await wait.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(v + 1, snap.Version);
    }

    [Fact]
    public async Task Wait_times_out_with_the_unchanged_image()
    {
        long v = _engine.Snapshot.Version;
        var wait = _engine.WaitForChangeAsync(v, TimeSpan.FromSeconds(25), CancellationToken.None);

        _time.Advance(TimeSpan.FromSeconds(24));
        await Task.Yield();
        Assert.False(wait.IsCompleted);

        _time.Advance(TimeSpan.FromSeconds(2));
        var snap = await wait.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(v, snap.Version);
    }
}

public class ConfigValidatorTests
{
    [Fact]
    public void Defaults_are_valid() => Assert.Empty(ConfigValidator.Validate(Defaults.Config));

    [Fact]
    public void Out_of_range_values_and_a_broken_priority_are_reported()
    {
        var appearance = new Dictionary<DisplayState, IReadOnlyList<LampSetting>>(Defaults.Appearance)
        {
            [DisplayState.Working] = [new(LampId.Blue, Effect.Pulse, 150, 0.05, 0)],
        };
        var settings = Defaults.Settings with { Priority = [DisplayState.Waiting, DisplayState.Waiting] };

        var errors = ConfigValidator.Validate(new RelayConfig(appearance, Defaults.Rules, settings));

        Assert.Equal(4, errors.Count);
    }
}
