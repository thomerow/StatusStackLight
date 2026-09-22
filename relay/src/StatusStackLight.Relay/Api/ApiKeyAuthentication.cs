using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;
using StatusStackLight.Relay.Data;

namespace StatusStackLight.Relay.Api;

public static class Roles
{
    public const string Admin  = "admin";
    public const string Lamp   = "lamp";
    public const string Client = "client";

    public static string Of(KeyRole role) => role == KeyRole.Lamp ? Lamp : Client;
}

/// <summary>Authenticates API requests by <c>Authorization: Bearer ssl_...</c>.</summary>
public sealed class ApiKeyAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    ApiKeyService keys)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "ApiKey";
    public const string KeyIdClaim = "key-id";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        string? header = Request.Headers.Authorization;
        if (string.IsNullOrEmpty(header) || !header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var identity = keys.Validate(header["Bearer ".Length..].Trim());
        if (identity is null) return Task.FromResult(AuthenticateResult.Fail("unknown api key"));

        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim(ClaimTypes.Name, identity.Name),
            new Claim(ClaimTypes.Role, Roles.Of(identity.Role)),
            new Claim(KeyIdClaim, identity.Id.ToString()),
        ], SchemeName));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, SchemeName)));
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status401Unauthorized;
        Response.Headers.WWWAuthenticate = "Bearer";
        await Response.WriteAsJsonAsync(new { error = "missing or unknown api key" });
    }

    protected override async Task HandleForbiddenAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status403Forbidden;
        await Response.WriteAsJsonAsync(new { error = "this api key is not allowed here" });
    }
}
