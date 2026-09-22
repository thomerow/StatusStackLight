using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;
using StatusStackLight.Relay.Api;
using StatusStackLight.Relay.Services;

namespace StatusStackLight.Relay.Pages;

[EnableRateLimiting("login")]
public sealed class LoginModel(AdminPassword admin) : PageModel
{
    public bool PasswordSet { get; private set; }
    public bool Failed { get; private set; }
    public string? ReturnUrl { get; private set; }

    public async Task OnGetAsync(string? returnUrl)
    {
        PasswordSet = await admin.IsSetAsync();
        ReturnUrl   = returnUrl;
    }

    public async Task<IActionResult> OnPostAsync(string? password, string? returnUrl)
    {
        PasswordSet = await admin.IsSetAsync();
        ReturnUrl   = returnUrl;

        if (!await admin.VerifyAsync(password ?? "")) {
            Failed = true;
            return Page();
        }

        var identity = new ClaimsIdentity(
            [new Claim(ClaimTypes.Name, "admin"), new Claim(ClaimTypes.Role, Roles.Admin)],
            CookieAuthenticationDefaults.AuthenticationScheme);
        await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme,
                                      new ClaimsPrincipal(identity),
                                      new AuthenticationProperties { IsPersistent = true });

        return LocalRedirect(Url.IsLocalUrl(returnUrl) ? returnUrl : Url.Content("~/"));
    }
}
