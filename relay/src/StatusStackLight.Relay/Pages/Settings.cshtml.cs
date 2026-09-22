using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Pages;

public sealed class SettingsModel(ConfigStore store) : PageModel
{
    [BindProperty] public List<DisplayState> Priority { get; set; } = [];
    [BindProperty] public double DoneMinutes     { get; set; }
    [BindProperty] public double StaleMinutes    { get; set; }
    [BindProperty] public double FlashSeconds    { get; set; }
    [BindProperty] public int    LongPollSeconds { get; set; }

    public IReadOnlyList<string> Errors { get; private set; } = [];

    public void OnGet()
    {
        var s = store.Current.Settings;
        Priority        = [.. s.Priority];
        DoneMinutes     = s.DoneMinutes;
        StaleMinutes    = s.StaleMinutes;
        FlashSeconds    = s.FlashSeconds;
        LongPollSeconds = s.LongPollSeconds;
    }

    public async Task<IActionResult> OnPostAsync()
    {
        var settings = new RelaySettings
        {
            Priority        = Priority,
            DoneMinutes     = DoneMinutes,
            StaleMinutes    = StaleMinutes,
            FlashSeconds    = FlashSeconds,
            LongPollSeconds = LongPollSeconds,
        };

        Errors = ModelState.IsValid
            ? await store.SaveAsync(store.Current with { Settings = settings })
            : ["Some values are not numbers."];
        if (Errors.Count > 0) return Page();

        TempData["Message"] = "Settings saved.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostResetAsync()
    {
        await store.SaveAsync(store.Current with { Settings = Defaults.Settings });
        TempData["Message"] = "Settings reset to the defaults.";
        return RedirectToPage();
    }
}
