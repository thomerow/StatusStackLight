using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Pages;

public sealed class IndexModel(RelayEngine engine) : PageModel
{
    public const string TestSession = "admin-test";

    public DisplaySnapshot Snapshot { get; private set; } = null!;
    public string RelayUrl => $"{Request.Scheme}://{Request.Host}{Request.PathBase}";

    public void OnGet() => Snapshot = engine.Snapshot;

    public IActionResult OnPostEvent(HookEvent ev)
    {
        bool applied = engine.Apply(ev, TestSession, "admin interface");
        TempData["Message"] = applied
            ? $"{ev} sent."
            : $"{ev} sent, but its rule does not apply in the current state - nothing changed.";
        return RedirectToPage();
    }

    public IActionResult OnPostAllOff()
    {
        engine.Clear();
        TempData["Message"] = "All sessions forgotten.";
        return RedirectToPage();
    }
}
