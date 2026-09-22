using System.Security.Claims;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Api;

public static class Policies
{
    /// <summary>Stack lights (and the admin, for the dashboard).</summary>
    public const string Lamp = "lamp";
    /// <summary>Hook scripts reporting events.</summary>
    public const string Client = "client";
    /// <summary>Anyone with a key, or the admin.</summary>
    public const string Reader = "reader";
}

public sealed record EventRequest(string? Event, string? Session, string? Host);

public static class ApiEndpoints
{
    public const int MaxSessionLength = 128;
    public const int MaxHostLength    = 64;

    /// <summary>Not a hook event: forgets all sessions, like -Event AllOff in LAN mode.</summary>
    public const string AllOff = "AllOff";

    public static void MapRelayApi(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1");

        api.MapPost("/events", PostEvent).RequireAuthorization(Policies.Client);
        api.MapGet("/lamps", GetLamps).RequireAuthorization(Policies.Lamp);
        api.MapGet("/status", GetStatus).RequireAuthorization(Policies.Reader);

        app.MapGet("/healthz", () => Results.Text("ok"));
    }

    private static IResult PostEvent(EventRequest request, RelayEngine engine)
    {
        if (string.IsNullOrWhiteSpace(request.Event)) return Error("event must not be empty");

        if (string.Equals(request.Event, AllOff, StringComparison.OrdinalIgnoreCase)) {
            engine.Clear();
            return Results.Ok(EventResponse(true, engine.Snapshot));
        }

        if (!Enum.TryParse<HookEvent>(request.Event, ignoreCase: true, out var ev)
            || !Enum.IsDefined(ev) || char.IsDigit(request.Event[0])) {
            return Results.BadRequest(new
            {
                error  = $"unknown event: {request.Event}",
                events = Enum.GetNames<HookEvent>().Append(AllOff),
            });
        }
        if (string.IsNullOrWhiteSpace(request.Session)) return Error("session must not be empty");
        if (request.Session.Length > MaxSessionLength) return Error($"session longer than {MaxSessionLength} characters");
        if (request.Host?.Length > MaxHostLength) return Error($"host longer than {MaxHostLength} characters");

        var host    = string.IsNullOrWhiteSpace(request.Host) ? null : request.Host.Trim();
        bool applied = engine.Apply(ev, request.Session, host);
        return Results.Ok(EventResponse(applied, engine.Snapshot));
    }

    /// <summary>
    /// Long poll. Answers at once if the lamp's version is not the current one, otherwise as
    /// soon as the image changes, at the latest after <c>wait</c> seconds with the unchanged image.
    /// </summary>
    private static async Task<IResult> GetLamps(long? version, int? wait, HttpContext http,
                                                RelayEngine engine, LampRegistry registry)
    {
        int maxWait = engine.Config.Settings.LongPollSeconds;
        int seconds = Math.Clamp(wait ?? maxWait, 0, maxWait);
        var name    = http.User.Identity?.Name ?? "?";
        bool isLamp = http.User.IsInRole(Roles.Lamp);

        if (isLamp) registry.Seen(name, http, version ?? 0, polling: true);
        var snapshot = await engine.WaitForChangeAsync(version ?? 0, TimeSpan.FromSeconds(seconds),
                                                       http.RequestAborted);
        if (isLamp) registry.Seen(name, http, snapshot.Version, polling: false);

        http.Response.Headers.CacheControl = "no-store";
        return Results.Ok(LampsResponse(snapshot));
    }

    private static IResult GetStatus(RelayEngine engine, LampRegistry registry, TimeProvider time)
    {
        var now      = time.GetUtcNow();
        var snapshot = engine.Snapshot;
        return Results.Ok(new
        {
            state   = snapshot.Situation.Main,
            error   = snapshot.Situation.Error,
            flash   = snapshot.Situation.Flash,
            version = snapshot.Version,
            // The session ID is shortened: enough to tell sessions apart, and it does not
            // expose more than needed to anyone holding a lamp key.
            sessions = engine.Sessions.Select(s => new
            {
                id    = s.Id.Length > 8 ? s.Id[..8] : s.Id,
                host  = s.Host,
                state = s.State,
                error = s.Error,
                idleSeconds = (int)(now - s.LastEvent).TotalSeconds,
            }),
            stackLights = registry.All.Select(l => new
            {
                name          = l.KeyName,
                remoteAddress = l.RemoteAddress,
                localAddress  = l.LocalAddress,
                firmware      = l.Firmware,
                lastSeen      = l.LastSeen,
                version       = l.Version,
                polling       = l.Polling,
            }),
            lamps = LampMap(snapshot),
        });
    }

    public static object LampsResponse(DisplaySnapshot s) => new
    {
        version = s.Version,
        state   = s.Situation.Main,
        error   = s.Situation.Error,
        lamps   = LampMap(s),
    };

    /// <summary>The lamps keyed by ID, exactly the body the firmware's POST /api/lamps takes.</summary>
    public static Dictionary<string, LampOutput> LampMap(DisplaySnapshot s) =>
        s.Lamps.OrderBy(kv => kv.Key).ToDictionary(kv => kv.Key.ToString().ToLowerInvariant(), kv => kv.Value);

    private static object EventResponse(bool applied, DisplaySnapshot s) => new
    {
        applied,
        state   = s.Situation.Main,
        error   = s.Situation.Error,
        version = s.Version,
    };

    private static IResult Error(string message) => Results.BadRequest(new { error = message });
}
