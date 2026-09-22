using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Pages;

/// <summary>Texts and small formatting helpers for the admin interface.</summary>
public static class Ui
{
    /// <summary>Top to bottom, as on the real stack light.</summary>
    public static readonly LampId[] StackOrder = [LampId.Red, LampId.Orange, LampId.Green, LampId.Blue, LampId.White];

    public static string Id(this LampId l)      => l.ToString().ToLowerInvariant();
    public static string Id(this Effect e)      => e.ToString().ToLowerInvariant();
    public static string Id(this DisplayState s) => s.ToString().ToLowerInvariant();

    public static string Color(LampId l) => l switch
    {
        LampId.White  => "#f8fafc",
        LampId.Blue   => "#3b82f6",
        LampId.Green  => "#22c55e",
        LampId.Orange => "#f59e0b",
        LampId.Red    => "#ef4444",
        _             => "#888",
    };

    public static string Describe(DisplayState s) => s switch
    {
        DisplayState.Ready   => "A session is open, nothing is going on.",
        DisplayState.Done    => "Just finished - there is something to read.",
        DisplayState.Working => "Claude is thinking or working.",
        DisplayState.Asking  => "Claude has a question for you.",
        DisplayState.Waiting => "Claude needs an approval - the work stands still until then.",
        DisplayState.Error   => "Something went wrong. Sits on top of the main state, latched until the next prompt.",
        DisplayState.Danger  => "Warning flash for a dangerous command. Sits on top of everything for a moment.",
        _                    => "",
    };

    public static string Describe(HookEvent e) => e switch
    {
        HookEvent.SessionStart     => "SessionStart - a session was opened.",
        HookEvent.UserPromptSubmit => "UserPromptSubmit - you sent a prompt.",
        HookEvent.Approval         => "Notification permission_prompt, PreToolUse ExitPlanMode - an approval is needed.",
        HookEvent.Question         => "Notification elicitation dialogs, PreToolUse AskUserQuestion - Claude asks.",
        HookEvent.ToolDone         => "PostToolUse - a tool has run (fires after every tool call).",
        HookEvent.Stop             => "Stop - Claude finished its response.",
        HookEvent.StopFailure      => "StopFailure - the response ended with an error.",
        HookEvent.ToolFailure      => "PostToolUseFailure - a tool call failed.",
        HookEvent.SessionEnd       => "SessionEnd - the session was closed.",
        HookEvent.Danger           => "PreToolUse Bash with a dangerous command (rm -rf, git push --force, ...). "
                                    + "The script checks the command locally; the text never leaves the computer.",
        _                          => "",
    };

    public static string Describe(StateAction a) => a switch
    {
        StateAction.Keep => "unchanged",
        StateAction.End  => "end session",
        _                => a.ToString().ToLowerInvariant(),
    };

    public static string Describe(ErrorAction a) => a switch
    {
        ErrorAction.Keep  => "unchanged",
        ErrorAction.Set   => "set",
        ErrorAction.Clear => "clear",
        _                 => "",
    };

    public static string Ago(DateTimeOffset? then, DateTimeOffset now)
    {
        if (then is null) return "never";
        var d = now - then.Value;
        if (d < TimeSpan.FromSeconds(60)) return $"{Math.Max(0, (int)d.TotalSeconds)} s ago";
        if (d < TimeSpan.FromMinutes(60)) return $"{(int)d.TotalMinutes} min ago";
        if (d < TimeSpan.FromHours(48))   return $"{(int)d.TotalHours} h ago";
        return $"{(int)d.TotalDays} days ago";
    }

    public static string Utc(DateTimeOffset? t) => t?.UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss 'UTC'") ?? "";
}
