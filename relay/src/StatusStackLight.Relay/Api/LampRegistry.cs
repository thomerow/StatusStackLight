using System.Collections.Concurrent;

namespace StatusStackLight.Relay.Api;

/// <summary>A stack light as last seen by the relay.</summary>
public sealed record LampContact(
    string KeyName, string? RemoteAddress, string? LocalAddress, string? Firmware,
    DateTimeOffset LastSeen, long Version, bool Polling);

/// <summary>
/// Remembers which stack lights poll, so the dashboard can show "last seen". In memory only:
/// a lamp that polls shows up again within one poll after a restart.
/// </summary>
public sealed class LampRegistry(TimeProvider time)
{
    public const string FirmwareHeader = "X-StackLight-Firmware";
    public const string AddressHeader  = "X-StackLight-Ip";

    private readonly ConcurrentDictionary<string, LampContact> _lamps = new();

    public void Seen(string keyName, HttpContext http, long version, bool polling)
    {
        string? Header(string name) => http.Request.Headers.TryGetValue(name, out var v) ? Clip(v.ToString()) : null;

        _lamps[keyName] = new LampContact(
            keyName,
            http.Connection.RemoteIpAddress?.ToString(),
            Header(AddressHeader),
            Header(FirmwareHeader),
            time.GetUtcNow(),
            version,
            polling);
    }

    public IReadOnlyList<LampContact> All => [.. _lamps.Values.OrderBy(l => l.KeyName)];

    private static string? Clip(string s) => s.Length == 0 ? null : s.Length > 64 ? s[..64] : s;
}
