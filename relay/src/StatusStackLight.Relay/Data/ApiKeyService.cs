using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;

namespace StatusStackLight.Relay.Data;

/// <summary>What an authenticated request knows about its key.</summary>
public sealed record KeyIdentity(int Id, string Name, KeyRole Role);

/// <summary>
/// Creates, checks and deletes API keys.
///
/// Every lamp poll and every hook checks a key, so the hashes are held in memory; the database
/// is only touched when keys change. "Last used" is collected in memory as well and written at
/// most once a minute - a lamp polls every 25 seconds, and that is no reason to write to disk.
/// </summary>
public sealed class ApiKeyService(IDbContextFactory<RelayDbContext> dbFactory, TimeProvider time)
{
    public const string KeyPrefix = "ssl_";

    private volatile IReadOnlyDictionary<string, KeyIdentity> _byHash = new Dictionary<string, KeyIdentity>();
    private readonly ConcurrentDictionary<int, DateTimeOffset> _lastUsed = new();

    public async Task LoadAsync()
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        _byHash = await db.ApiKeys.AsNoTracking()
                        .ToDictionaryAsync(k => k.Hash, k => new KeyIdentity(k.Id, k.Name, k.Role));
    }

    /// <summary>Checks a key as sent by a client. Null if it is unknown.</summary>
    public KeyIdentity? Validate(string key)
    {
        if (!key.StartsWith(KeyPrefix, StringComparison.Ordinal)) return null;
        if (!_byHash.TryGetValue(Hash(key), out var identity)) return null;
        _lastUsed[identity.Id] = time.GetUtcNow();
        return identity;
    }

    public async Task<IReadOnlyList<ApiKey>> ListAsync()
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var keys = await db.ApiKeys.AsNoTracking().ToListAsync();
        foreach (var k in keys) {
            if (_lastUsed.TryGetValue(k.Id, out var used)) k.LastUsedAt = used;
        }
        return [.. keys.OrderBy(k => k.Role).ThenBy(k => k.Name, StringComparer.OrdinalIgnoreCase)];
    }

    /// <summary>Creates a key. The plain key is only in the return value - it is not stored.</summary>
    public async Task<(ApiKey Entity, string Key)> CreateAsync(string name, KeyRole role)
    {
        var key = KeyPrefix + WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var entity = new ApiKey
        {
            Name      = name.Trim(),
            Role      = role,
            Hash      = Hash(key),
            Prefix    = key[..(KeyPrefix.Length + 6)],
            CreatedAt = time.GetUtcNow(),
        };

        await using (var db = await dbFactory.CreateDbContextAsync()) {
            db.ApiKeys.Add(entity);
            await db.SaveChangesAsync();
        }
        await LoadAsync();
        return (entity, key);
    }

    public async Task RenameAsync(int id, string name)
    {
        await using (var db = await dbFactory.CreateDbContextAsync()) {
            await db.ApiKeys.Where(k => k.Id == id)
                    .ExecuteUpdateAsync(s => s.SetProperty(k => k.Name, name.Trim()));
        }
        await LoadAsync();
    }

    public async Task DeleteAsync(int id)
    {
        await using (var db = await dbFactory.CreateDbContextAsync()) {
            await db.ApiKeys.Where(k => k.Id == id).ExecuteDeleteAsync();
        }
        _lastUsed.TryRemove(id, out _);
        await LoadAsync();
    }

    /// <summary>Writes the collected "last used" times. Called by the timer service.</summary>
    public async Task FlushLastUsedAsync()
    {
        if (_lastUsed.IsEmpty) return;
        await using var db = await dbFactory.CreateDbContextAsync();
        var keys = await db.ApiKeys.ToListAsync();
        foreach (var k in keys) {
            if (_lastUsed.TryGetValue(k.Id, out var used) && used != k.LastUsedAt) k.LastUsedAt = used;
        }
        await db.SaveChangesAsync();
    }

    private static string Hash(string key) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
}
