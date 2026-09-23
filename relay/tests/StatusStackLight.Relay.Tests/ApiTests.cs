using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Tests;

/// <summary>Starts the relay with its own empty data directory.</summary>
public class RelayFactory : WebApplicationFactory<Program>
{
    public const string TestPassword = "test-password";

    public string DataDirectory { get; } =
        Path.Combine(Path.GetTempPath(), "ssl-relay-tests", Guid.NewGuid().ToString("N"));

    /// <summary>The sub-path the relay runs under, empty for the root.</summary>
    public virtual string PathBase => "";

    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseSetting("DataDirectory", DataDirectory);
        if (PathBase.Length > 0) builder.UseSetting("PathBase", PathBase);
    }

    public async Task<HttpClient> ClientWithKeyAsync(KeyRole role)
    {
        var (_, key) = await Services.GetRequiredService<ApiKeyService>().CreateAsync($"test {role}", role);
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", key);
        return client;
    }

    /// <summary>A client logged in as the admin, as a browser would be.</summary>
    public async Task<HttpClient> AdminClientAsync()
    {
        await Services.GetRequiredService<Services.AdminPassword>().SetAsync(TestPassword);
        var client = CreateClient();
        var login = await client.GetStringAsync($"{PathBase}/login");
        var r = await client.PostAsync($"{PathBase}/login", Form(login, ("password", TestPassword)));
        r.EnsureSuccessStatusCode();
        return client;
    }

    /// <summary>A form post with the antiforgery token out of <paramref name="html"/>.</summary>
    public static FormUrlEncodedContent Form(string html, params (string Name, string Value)[] fields) =>
        new([.. fields.Select(f => KeyValuePair.Create(f.Name, f.Value)),
             KeyValuePair.Create("__RequestVerificationToken", AntiforgeryToken(html))]);

    public static string AntiforgeryToken(string html) =>
        Regex.Match(html, "__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value;

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        try { Directory.Delete(DataDirectory, recursive: true); } catch (IOException) { }
    }
}

public class ApiTests : IClassFixture<RelayFactory>
{
    private readonly RelayFactory _factory;

    public ApiTests(RelayFactory factory)
    {
        _factory = factory;
        _factory.Services.GetRequiredService<RelayEngine>().Clear();
    }

    private static Task<HttpResponseMessage> Send(HttpClient c, string ev, string session = "s1") =>
        c.PostAsJsonAsync("/api/v1/events", new { @event = ev, session, host = "pc" });

    private static async Task<JsonElement> Json(HttpResponseMessage r) =>
        JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;

    [Fact]
    public async Task Health_needs_no_key()
    {
        var r = await _factory.CreateClient().GetAsync("/healthz");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
    }

    [Theory]
    [InlineData("/api/v1/lamps")]
    [InlineData("/api/v1/status")]
    public async Task Without_key_the_api_answers_401_not_a_redirect(string path)
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        var r = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task Unknown_key_is_rejected()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "ssl_nonsense");
        var r = await Send(client, "Stop");
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task Roles_are_separated()
    {
        var lamp   = await _factory.ClientWithKeyAsync(KeyRole.Lamp);
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);

        Assert.Equal(HttpStatusCode.Forbidden, (await Send(lamp, "Stop")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/v1/lamps?wait=0")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/status")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await lamp.GetAsync("/api/v1/status")).StatusCode);
    }

    [Fact]
    public async Task Event_changes_the_lamps_in_firmware_format()
    {
        var lamp   = await _factory.ClientWithKeyAsync(KeyRole.Lamp);
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);

        var ev = await Json(await Send(client, "userpromptsubmit"));
        Assert.True(ev.GetProperty("applied").GetBoolean());
        Assert.Equal("working", ev.GetProperty("state").GetString());

        var body = await Json(await lamp.GetAsync("/api/v1/lamps?version=0&wait=0"));
        var lamps = body.GetProperty("lamps");
        Assert.Equal(["white", "blue", "green", "orange", "red"],
                     lamps.EnumerateObject().Select(p => p.Name).ToArray());

        var blue = lamps.GetProperty("blue");
        Assert.True(blue.GetProperty("on").GetBoolean());
        Assert.Equal("pulse", blue.GetProperty("effect").GetString());
        Assert.Equal(70, blue.GetProperty("brightness").GetInt32());
        Assert.Equal(0.3, blue.GetProperty("frequency").GetDouble());
        Assert.Equal(50, blue.GetProperty("duty").GetInt32());
        Assert.Equal(5, blue.EnumerateObject().Count());
    }

    [Fact]
    public async Task Bad_events_are_rejected()
    {
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);

        Assert.Equal(HttpStatusCode.BadRequest, (await Send(client, "Nonsense")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Send(client, "3")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Send(client, "Stop", session: "")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Send(client, "Stop", session: new string('x', 129))).StatusCode);
    }

    [Fact]
    public async Task All_off_clears_every_session()
    {
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);
        await Send(client, "Approval", "a");
        await Send(client, "Stop", "b");

        var r = await Json(await Send(client, "AllOff", ""));

        Assert.Equal(JsonValueKind.Null, r.GetProperty("state").ValueKind);
        Assert.Empty(_factory.Services.GetRequiredService<RelayEngine>().Sessions);
    }

    [Fact]
    public async Task Long_poll_waits_for_a_change()
    {
        var lamp   = await _factory.ClientWithKeyAsync(KeyRole.Lamp);
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);
        long version = (await Json(await lamp.GetAsync("/api/v1/lamps?wait=0"))).GetProperty("version").GetInt64();

        var poll = lamp.GetAsync($"/api/v1/lamps?version={version}&wait=20");
        await Task.Delay(300);
        Assert.False(poll.IsCompleted);

        await Send(client, "Approval");
        var body = await Json(await poll.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.Equal(version + 1, body.GetProperty("version").GetInt64());
        Assert.Equal("waiting", body.GetProperty("state").GetString());
    }

    [Fact]
    public async Task Long_poll_returns_the_unchanged_image_after_the_wait()
    {
        var lamp = await _factory.ClientWithKeyAsync(KeyRole.Lamp);
        long version = (await Json(await lamp.GetAsync("/api/v1/lamps?wait=0"))).GetProperty("version").GetInt64();

        var started = DateTime.UtcNow;
        var body = await Json(await lamp.GetAsync($"/api/v1/lamps?version={version}&wait=1"));

        Assert.True(DateTime.UtcNow - started >= TimeSpan.FromSeconds(0.9));
        Assert.Equal(version, body.GetProperty("version").GetInt64());
    }

    [Fact]
    public async Task Status_lists_sessions_and_polling_lamps()
    {
        var lamp   = await _factory.ClientWithKeyAsync(KeyRole.Lamp);
        var client = await _factory.ClientWithKeyAsync(KeyRole.Client);
        await Send(client, "SessionStart", "0123456789abcdef");
        lamp.DefaultRequestHeaders.Add("X-StackLight-Firmware", "1.1.0");
        await lamp.GetAsync("/api/v1/lamps?wait=0");

        var status = await Json(await client.GetAsync("/api/v1/status"));

        var session = Assert.Single(status.GetProperty("sessions").EnumerateArray());
        Assert.Equal("01234567", session.GetProperty("id").GetString());
        Assert.Equal("pc", session.GetProperty("host").GetString());
        Assert.Contains(status.GetProperty("stackLights").EnumerateArray(),
                        l => l.GetProperty("firmware").GetString() == "1.1.0");
    }

    [Fact]
    public async Task Config_survives_a_reload()
    {
        var store  = _factory.Services.GetRequiredService<ConfigStore>();
        var config = store.Current with { Settings = store.Current.Settings with { DoneMinutes = 7 } };
        Assert.Empty(await store.SaveAsync(config));

        await using var db = await _factory.Services
            .GetRequiredService<Microsoft.EntityFrameworkCore.IDbContextFactory<RelayDbContext>>()
            .CreateDbContextAsync();
        var loaded = ConfigStore.Load(db);

        Assert.Equal(7, loaded.Settings.DoneMinutes);
        Assert.Equal(Defaults.Settings.Priority, loaded.Settings.Priority);
        Assert.Equal(Defaults.Appearance[DisplayState.Waiting], loaded.Appearance[DisplayState.Waiting]);
        Assert.Equal(Defaults.Rules[HookEvent.ToolDone].OnlyWhen, loaded.Rules[HookEvent.ToolDone].OnlyWhen);

        Assert.Empty(await store.SaveAsync(Defaults.Config));
    }
}

public class AdminUiTests : IClassFixture<RelayFactory>
{
    private readonly RelayFactory _factory;
    public AdminUiTests(RelayFactory factory) => _factory = factory;

    [Theory]
    [InlineData("/")]
    [InlineData("/display")]
    [InlineData("/events")]
    [InlineData("/settings")]
    [InlineData("/keys")]
    public async Task Admin_pages_redirect_to_login(string path)
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        var r = await client.GetAsync(path);

        Assert.Equal(HttpStatusCode.Redirect, r.StatusCode);
        Assert.StartsWith("/login", r.Headers.Location?.PathAndQuery);
    }

    [Fact]
    public async Task Login_explains_how_to_set_the_password()
    {
        var html = await _factory.CreateClient().GetStringAsync("/login");
        Assert.Contains("set-password", html);
    }
}

/// <summary>The relay as it runs behind a reverse proxy under a sub-path.</summary>
public sealed class SubPathFactory : RelayFactory
{
    public override string PathBase => "/stacklight";
}

public class SubPathTests : IClassFixture<SubPathFactory>
{
    private readonly SubPathFactory _factory;
    public SubPathTests(SubPathFactory factory) => _factory = factory;

    /// <summary>
    /// The dashboard sits at the root, so its forms must not post to the bare sub-path: a proxy
    /// that answers /stacklight with a redirect to /stacklight/ turns the POST into a GET, and the
    /// buttons would silently reload the page.
    /// </summary>
    [Fact]
    public async Task Test_buttons_post_to_the_sub_path_with_a_trailing_slash()
    {
        var client = await _factory.AdminClientAsync();

        var html = await client.GetStringAsync("/stacklight/");

        Assert.Contains("action=\"/stacklight/?handler=Event\"", html);
        Assert.Contains("action=\"/stacklight/?handler=AllOff\"", html);
        Assert.NotEqual("", RelayFactory.AntiforgeryToken(html));
    }

    [Fact]
    public async Task A_test_event_from_the_dashboard_arrives()
    {
        var engine = _factory.Services.GetRequiredService<RelayEngine>();
        engine.Clear();
        var client = await _factory.AdminClientAsync();
        var html = await client.GetStringAsync("/stacklight/");

        var r = await client.PostAsync("/stacklight/?handler=Event",
                                       RelayFactory.Form(html, ("ev", nameof(HookEvent.UserPromptSubmit))));

        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal(DisplayState.Working, engine.Snapshot.Situation.Main);
    }
}

public class ShutdownTests
{
    [Fact]
    public async Task Waiting_long_polls_are_answered_on_shutdown()
    {
        using var factory = new RelayFactory();
        var lamp = await factory.ClientWithKeyAsync(KeyRole.Lamp);
        var first = JsonDocument.Parse(await lamp.GetStringAsync("/api/v1/lamps?wait=0")).RootElement;
        long version = first.GetProperty("version").GetInt64();

        var poll = lamp.GetAsync($"/api/v1/lamps?version={version}&wait=20");
        await Task.Delay(300);
        Assert.False(poll.IsCompleted);

        factory.Services.GetRequiredService<Microsoft.Extensions.Hosting.IHostApplicationLifetime>().StopApplication();

        var r = await poll.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
    }
}
