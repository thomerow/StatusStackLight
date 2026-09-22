using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Pages;

public sealed class EventsModel(ConfigStore store) : PageModel
{
    public sealed class RuleForm
    {
        public HookEvent          Event    { get; set; }
        public StateAction        State    { get; set; }
        public ErrorAction        Error    { get; set; }
        public List<SessionState> OnlyWhen { get; set; } = [];
        public bool               Flash    { get; set; }
    }

    [BindProperty] public List<RuleForm> Rules { get; set; } = [];
    public IReadOnlyList<string> Errors { get; private set; } = [];

    public void OnGet() =>
        Rules = Enum.GetValues<HookEvent>().Select(ev => {
            var r = store.Current.Rules.GetValueOrDefault(ev) ?? new EventRule();
            return new RuleForm { Event = ev, State = r.State, Error = r.Error, OnlyWhen = [.. r.OnlyWhen], Flash = r.Flash };
        }).ToList();

    public async Task<IActionResult> OnPostAsync()
    {
        var rules = Rules.ToDictionary(
            r => r.Event,
            r => new EventRule { State = r.State, Error = r.Error, OnlyWhen = [.. r.OnlyWhen.Distinct()], Flash = r.Flash });

        Errors = ModelState.IsValid
            ? await store.SaveAsync(store.Current with { Rules = rules })
            : ["The form could not be read."];
        if (Errors.Count > 0) return Page();

        TempData["Message"] = "Event rules saved.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostResetAsync()
    {
        await store.SaveAsync(store.Current with { Rules = Defaults.Rules });
        TempData["Message"] = "Event rules reset to the defaults.";
        return RedirectToPage();
    }
}
