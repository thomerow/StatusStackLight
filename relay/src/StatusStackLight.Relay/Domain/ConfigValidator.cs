namespace StatusStackLight.Relay.Domain;

/// <summary>
/// Checks a configuration before it is stored. The ranges are those of the firmware - a value
/// the stack light would reject must never reach it, otherwise it would drop the whole image.
/// </summary>
public static class ConfigValidator
{
    public const int    BrightnessMin = 0,    BrightnessMax = 100;
    public const double FrequencyMin  = 0.1,  FrequencyMax  = 20.0;
    public const int    DutyMin       = 1,    DutyMax       = 99;

    public static IReadOnlyList<string> Validate(RelayConfig config)
    {
        var errors = new List<string>();

        foreach (var state in Enum.GetValues<DisplayState>()) {
            if (!config.Appearance.TryGetValue(state, out var lamps)) {
                errors.Add($"{state}: no appearance defined");
                continue;
            }
            foreach (var group in lamps.GroupBy(l => l.Lamp).Where(g => g.Count() > 1)) {
                errors.Add($"{state}: lamp {group.Key} used more than once");
            }
            foreach (var l in lamps) {
                if (!Enum.IsDefined(l.Lamp))
                    errors.Add($"{state}: unknown lamp {l.Lamp}");
                if (!Enum.IsDefined(l.Effect))
                    errors.Add($"{state}/{l.Lamp}: unknown effect {l.Effect}");
                if (l.Brightness is < BrightnessMin or > BrightnessMax)
                    errors.Add($"{state}/{l.Lamp}: brightness must be {BrightnessMin}...{BrightnessMax}");
                if (!(l.Frequency >= FrequencyMin && l.Frequency <= FrequencyMax))
                    errors.Add($"{state}/{l.Lamp}: frequency must be {FrequencyMin}...{FrequencyMax} Hz");
                if (l.Duty is < DutyMin or > DutyMax)
                    errors.Add($"{state}/{l.Lamp}: duty must be {DutyMin}...{DutyMax} %");
            }
        }

        foreach (var ev in Enum.GetValues<HookEvent>()) {
            if (!config.Rules.ContainsKey(ev)) errors.Add($"{ev}: no rule defined");
        }

        var s = config.Settings;
        if (s.Priority.Count != DisplayStates.Main.Count
            || s.Priority.Distinct().Count() != s.Priority.Count
            || !s.Priority.All(DisplayStates.IsMain)) {
            errors.Add("priority must list each of Ready, Done, Working, Asking, Waiting exactly once");
        }
        if (!(s.DoneMinutes >= 0 && s.DoneMinutes <= 24 * 60))
            errors.Add("done minutes must be 0...1440");
        if (!(s.StaleMinutes >= 1 && s.StaleMinutes <= 7 * 24 * 60))
            errors.Add("stale minutes must be 1...10080");
        if (!(s.FlashSeconds >= 0.1 && s.FlashSeconds <= 30))
            errors.Add("flash seconds must be 0.1...30");
        if (s.LongPollSeconds is < 5 or > 55)
            errors.Add("long poll seconds must be 5...55");

        return errors;
    }
}
