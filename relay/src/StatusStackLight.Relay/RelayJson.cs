using System.Text.Json;
using System.Text.Json.Serialization;

namespace StatusStackLight.Relay;

/// <summary>
/// JSON conventions of the relay, the same as the firmware's: camelCase names, enums as
/// lowercase strings ("pulse", "orange").
/// </summary>
public static class RelayJson
{
    public static JsonSerializerOptions Options { get; } = Configure(new JsonSerializerOptions());

    public static JsonSerializerOptions Configure(JsonSerializerOptions o)
    {
        o.PropertyNamingPolicy        = JsonNamingPolicy.CamelCase;
        o.DictionaryKeyPolicy         = JsonNamingPolicy.CamelCase;
        o.PropertyNameCaseInsensitive = true;
        o.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return o;
    }
}
