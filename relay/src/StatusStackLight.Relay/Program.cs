// StatusStackLight relay - the stack light polls it, the Claude Code hooks report to it.
//
// Structure:
//   Domain/    display logic: sessions, rules, lamp image (no ASP.NET dependencies)
//   Data/      SQLite: configuration and API keys
//   Api/       JSON API for stack lights and hook scripts, API key authentication
//   Pages/     admin interface (Razor Pages, cookie login)
//   Services/  timer for time-driven transitions, admin password
//
// Command line: "set-password" sets the admin password and exits.

using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using StatusStackLight.Relay;
using StatusStackLight.Relay.Api;
using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;
using StatusStackLight.Relay.Services;

var builder = WebApplication.CreateBuilder(args);

// Everything the relay keeps: database and data protection keys (for the login cookie).
var dataDirectory = Path.GetFullPath(builder.Configuration["DataDirectory"] ?? "App_Data",
                                     builder.Environment.ContentRootPath);
Directory.CreateDirectory(dataDirectory);

builder.Services.AddDbContextFactory<RelayDbContext>(o =>
    o.UseSqlite($"Data Source={Path.Combine(dataDirectory, "relay.db")}"));
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(dataDirectory, "keys")))
    .SetApplicationName("StatusStackLight.Relay");

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton(sp => {
    using var db = sp.GetRequiredService<IDbContextFactory<RelayDbContext>>().CreateDbContext();
    return new RelayEngine(ConfigStore.Load(db), sp.GetRequiredService<TimeProvider>());
});
builder.Services.AddSingleton<ConfigStore>();
builder.Services.AddSingleton<ApiKeyService>();
builder.Services.AddSingleton<LampRegistry>();
builder.Services.AddSingleton<AdminPassword>();
builder.Services.AddHostedService<RelayTimerService>();

builder.Services.ConfigureHttpJsonOptions(o => RelayJson.Configure(o.SerializerOptions));

// Behind nginx: take client address and scheme from the proxy. Only proxies on the same
// machine are trusted (the default), so nobody can fake them from outside.
builder.Services.Configure<ForwardedHeadersOptions>(o =>
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto);

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(o => {
        o.LoginPath          = "/login";
        o.LogoutPath         = "/logout";
        o.Cookie.Name        = "ssl-relay";
        o.Cookie.HttpOnly    = true;
        o.Cookie.SameSite    = SameSiteMode.Strict;
        o.ExpireTimeSpan     = TimeSpan.FromDays(14);
        o.SlidingExpiration  = true;
        // The API answers with a status code, not with a redirect to the login page. The API
        // key handler has usually written the answer already.
        o.Events.OnRedirectToLogin = ctx => ApiStatus(ctx, StatusCodes.Status401Unauthorized);
        o.Events.OnRedirectToAccessDenied = ctx => ApiStatus(ctx, StatusCodes.Status403Forbidden);
    })
    .AddScheme<AuthenticationSchemeOptions, ApiKeyAuthenticationHandler>(ApiKeyAuthenticationHandler.SchemeName, null);

string[] bothSchemes = [ApiKeyAuthenticationHandler.SchemeName, CookieAuthenticationDefaults.AuthenticationScheme];
builder.Services.AddAuthorization(o => {
    o.AddPolicy(Policies.Lamp, p => p.AddAuthenticationSchemes(bothSchemes)
                                     .RequireRole(Roles.Lamp, Roles.Admin));
    // Events only with a key: the admin interface triggers test events through its own
    // form handlers, which are protected against CSRF.
    o.AddPolicy(Policies.Client, p => p.AddAuthenticationSchemes(ApiKeyAuthenticationHandler.SchemeName)
                                       .RequireRole(Roles.Client));
    o.AddPolicy(Policies.Reader, p => p.AddAuthenticationSchemes(bothSchemes)
                                       .RequireRole(Roles.Lamp, Roles.Client, Roles.Admin));
});

builder.Services.AddRateLimiter(o => {
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("login", http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "?",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
});

builder.Services.AddRazorPages(o => {
    o.Conventions.AuthorizeFolder("/");
    o.Conventions.AllowAnonymousToPage("/Login");
});

var app = builder.Build();

await using (var scope = app.Services.CreateAsyncScope()) {
    var dbFactory = scope.ServiceProvider.GetRequiredService<IDbContextFactory<RelayDbContext>>();
    await using var db = await dbFactory.CreateDbContextAsync();
    await db.Database.MigrateAsync();
}

if (args is ["set-password", ..]) {
    return await app.Services.GetRequiredService<AdminPassword>().RunCommandAsync();
}

await app.Services.GetRequiredService<ApiKeyService>().LoadAsync();

app.UseForwardedHeaders();
// Served under a sub-path, e.g. https://example.org/stacklight/ behind nginx.
var pathBase = app.Configuration["PathBase"];
if (!string.IsNullOrEmpty(pathBase)) app.UsePathBase(pathBase);

app.UseStaticFiles();
app.UseRouting();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapRelayApi();
app.MapRazorPages();

await app.RunAsync();
return 0;

static Task ApiStatus(RedirectContext<CookieAuthenticationOptions> ctx, int status)
{
    if (ctx.Request.Path.StartsWithSegments("/api")) {
        if (!ctx.Response.HasStarted) ctx.Response.StatusCode = status;
    } else {
        ctx.Response.Redirect(ctx.RedirectUri);
    }
    return Task.CompletedTask;
}

// For WebApplicationFactory in the tests.
public partial class Program;
