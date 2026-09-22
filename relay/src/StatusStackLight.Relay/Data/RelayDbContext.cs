using Microsoft.EntityFrameworkCore;

namespace StatusStackLight.Relay.Data;

public enum KeyRole { Lamp, Client }

/// <summary>
/// An API key. Only the SHA-256 hash of the key is stored; the key itself is shown once when it
/// is created. The keys are long random strings, so a plain hash is enough - unlike passwords,
/// there is nothing to guess.
/// </summary>
public sealed class ApiKey
{
    public int            Id         { get; set; }
    public required string Name      { get; set; }
    public KeyRole        Role       { get; set; }
    public required string Hash      { get; set; }
    /// <summary>The first characters of the key, so it can be recognised in the list.</summary>
    public required string Prefix    { get; set; }
    public DateTimeOffset CreatedAt  { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }
}

/// <summary>
/// A piece of configuration as JSON: appearance, rules, settings, admin password hash. The
/// configuration is always read and written as a whole per section, so a document per section
/// is simpler than a table per concept - and adding a field needs no migration.
/// </summary>
public sealed class ConfigEntry
{
    public required string Key  { get; set; }
    public required string Json { get; set; }
}

public sealed class RelayDbContext(DbContextOptions<RelayDbContext> options) : DbContext(options)
{
    public DbSet<ApiKey>      ApiKeys       => Set<ApiKey>();
    public DbSet<ConfigEntry> ConfigEntries => Set<ConfigEntry>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<ApiKey>(e => {
            e.HasIndex(k => k.Hash).IsUnique();
            e.Property(k => k.Role).HasConversion<string>();
            e.Property(k => k.Name).HasMaxLength(64);
        });
        b.Entity<ConfigEntry>(e => e.HasKey(c => c.Key));
    }
}
