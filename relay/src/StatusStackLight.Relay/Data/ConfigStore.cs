using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Data;

/// <summary>
/// Loads and saves the configuration. Every save goes straight to the engine, so the stack
/// light shows a change in the admin interface on its next poll - that is, at once.
/// </summary>
public sealed class ConfigStore(IDbContextFactory<RelayDbContext> dbFactory, RelayEngine engine)
{
    private const string AppearanceKey = "appearance";
    private const string RulesKey      = "rules";
    private const string SettingsKey   = "settings";
    private const string PasswordKey   = "admin-password";

    /// <summary>Reads the stored configuration; missing sections get the factory defaults.</summary>
    public static RelayConfig Load(RelayDbContext db)
    {
        var entries = db.ConfigEntries.AsNoTracking().ToDictionary(e => e.Key, e => e.Json);

        T Read<T>(string key, T fallback) =>
            entries.TryGetValue(key, out var json)
                ? JsonSerializer.Deserialize<T>(json, RelayJson.Options) ?? fallback
                : fallback;

        var config = new RelayConfig(
            Read(AppearanceKey, Defaults.Appearance),
            Read(RulesKey, Defaults.Rules),
            Read(SettingsKey, Defaults.Settings));

        // Fill in what a stored section lacks - a state or event added in a later version.
        var appearance = Defaults.Appearance.ToDictionary(
            kv => kv.Key, kv => config.Appearance.GetValueOrDefault(kv.Key) ?? kv.Value);
        var rules = Defaults.Rules.ToDictionary(
            kv => kv.Key, kv => config.Rules.GetValueOrDefault(kv.Key) ?? kv.Value);
        return config with { Appearance = appearance, Rules = rules };
    }

    public RelayConfig Current => engine.Config;

    /// <summary>Validates and stores a new configuration. Returns the errors, empty on success.</summary>
    public async Task<IReadOnlyList<string>> SaveAsync(RelayConfig config)
    {
        var errors = ConfigValidator.Validate(config);
        if (errors.Count > 0) return errors;

        await using var db = await dbFactory.CreateDbContextAsync();
        await Upsert(db, AppearanceKey, config.Appearance);
        await Upsert(db, RulesKey, config.Rules);
        await Upsert(db, SettingsKey, config.Settings);
        await db.SaveChangesAsync();

        engine.UpdateConfig(config);
        return [];
    }

    public async Task<string?> GetPasswordHashAsync()
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entry = await db.ConfigEntries.FindAsync(PasswordKey);
        return entry is null ? null : JsonSerializer.Deserialize<string>(entry.Json);
    }

    public async Task SetPasswordHashAsync(string hash)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        await Upsert(db, PasswordKey, hash);
        await db.SaveChangesAsync();
    }

    private static async Task Upsert<T>(RelayDbContext db, string key, T value)
    {
        var json  = JsonSerializer.Serialize(value, RelayJson.Options);
        var entry = await db.ConfigEntries.FindAsync(key);
        if (entry is null) db.ConfigEntries.Add(new ConfigEntry { Key = key, Json = json });
        else entry.Json = json;
    }
}
