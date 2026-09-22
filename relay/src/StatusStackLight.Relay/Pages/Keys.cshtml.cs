using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using StatusStackLight.Relay.Data;

namespace StatusStackLight.Relay.Pages;

public sealed class KeysModel(ApiKeyService keys) : PageModel
{
    public const int MaxNameLength = 64;

    public IReadOnlyList<ApiKey> Keys { get; private set; } = [];
    public string? NewKey { get; private set; }
    public string? NewKeyName { get; private set; }
    public string? Error { get; private set; }

    public async Task OnGetAsync() => Keys = await keys.ListAsync();

    /// <summary>No redirect afterwards: the new key must be shown exactly once, in this response.</summary>
    public async Task<IActionResult> OnPostCreateAsync(string? name, KeyRole role)
    {
        if (CheckName(name) is { } error) {
            Error = error;
        } else if (!Enum.IsDefined(role)) {
            Error = "Unknown role.";
        } else {
            (_, NewKey) = await keys.CreateAsync(name!, role);
            NewKeyName  = name!.Trim();
        }
        Keys = await keys.ListAsync();
        return Page();
    }

    public async Task<IActionResult> OnPostRenameAsync(int id, string? name)
    {
        if (CheckName(name) is { } error) {
            Error = error;
            Keys  = await keys.ListAsync();
            return Page();
        }
        await keys.RenameAsync(id, name!);
        TempData["Message"] = "Key renamed.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostDeleteAsync(int id)
    {
        await keys.DeleteAsync(id);
        TempData["Message"] = "Key deleted.";
        return RedirectToPage();
    }

    private static string? CheckName(string? name) =>
        string.IsNullOrWhiteSpace(name) ? "The name must not be empty."
        : name.Trim().Length > MaxNameLength ? $"The name must not be longer than {MaxNameLength} characters."
        : null;
}
