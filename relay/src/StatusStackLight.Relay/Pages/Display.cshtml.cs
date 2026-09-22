using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Pages;

public sealed class DisplayModel(ConfigStore store) : PageModel
{
    public sealed class LampForm
    {
        public LampId Lamp       { get; set; }
        public bool   Use        { get; set; }
        public Effect Effect     { get; set; } = Effect.Steady;
        public int    Brightness { get; set; } = 100;
        public double Frequency  { get; set; } = 1.0;
        public int    Duty       { get; set; } = 50;
    }

    public sealed class StateForm
    {
        public DisplayState   State { get; set; }
        public List<LampForm> Lamps { get; set; } = [];
    }

    [BindProperty] public List<StateForm> States { get; set; } = [];
    public IReadOnlyList<string> Errors { get; private set; } = [];

    /// <summary>All lamps off - relay.js fills in the preview from the form.</summary>
    public IReadOnlyDictionary<LampId, LampOutput> Empty { get; } =
        Enum.GetValues<LampId>().ToDictionary(l => l, _ => LampOutput.Unused);

    public void OnGet() => States = ToForm(store.Current.Appearance);

    public async Task<IActionResult> OnPostAsync()
    {
        var appearance = States.ToDictionary(
            s => s.State,
            s => (IReadOnlyList<LampSetting>)s.Lamps
                .Where(l => l.Use)
                .Select(l => new LampSetting(l.Lamp, l.Effect, l.Brightness, l.Frequency, l.Duty))
                .ToList());

        Errors = ModelState.IsValid
            ? await store.SaveAsync(store.Current with { Appearance = appearance })
            : ["Some values are not numbers."];
        if (Errors.Count > 0) return Page();

        TempData["Message"] = "Display saved - the stack light shows it on its next poll.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostResetAsync()
    {
        await store.SaveAsync(store.Current with { Appearance = Defaults.Appearance });
        TempData["Message"] = "Display reset to the defaults.";
        return RedirectToPage();
    }

    private static List<StateForm> ToForm(IReadOnlyDictionary<DisplayState, IReadOnlyList<LampSetting>> appearance) =>
        Enum.GetValues<DisplayState>().Select(state => new StateForm
        {
            State = state,
            Lamps = Ui.StackOrder.Select(lamp => {
                var s = appearance.GetValueOrDefault(state)?.FirstOrDefault(x => x.Lamp == lamp);
                return s is null
                    ? new LampForm { Lamp = lamp }
                    : new LampForm { Lamp = lamp, Use = true, Effect = s.Effect, Brightness = s.Brightness,
                                     Frequency = s.Frequency, Duty = s.Duty };
            }).ToList(),
        }).ToList();
}
