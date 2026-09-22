using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Services;

/// <summary>
/// Drives the transitions no event triggers: Done falls back to Ready, crashed sessions are
/// forgotten, the warning flash ends. Replaces the straggler process (-Event Tick) of the
/// script's LAN mode.
///
/// One second is fine enough for all of them - the shortest is the warning flash of 1.2 s,
/// which then lasts 1.2...2.2 s. Nobody measures that.
/// </summary>
public sealed class RelayTimerService(RelayEngine engine, ApiKeyService keys, ILogger<RelayTimerService> log)
    : BackgroundService
{
    private static readonly TimeSpan Interval   = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan FlushEvery = TimeSpan.FromMinutes(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        var sinceFlush = TimeSpan.Zero;

        try {
            while (await timer.WaitForNextTickAsync(stoppingToken)) {
                engine.Tick();

                sinceFlush += Interval;
                if (sinceFlush >= FlushEvery) {
                    sinceFlush = TimeSpan.Zero;
                    await FlushAsync();
                }
            }
        } catch (OperationCanceledException) {
        }

        await FlushAsync();
    }

    private async Task FlushAsync()
    {
        try {
            await keys.FlushLastUsedAsync();
        } catch (Exception e) {
            log.LogWarning(e, "could not store the last use of the api keys");
        }
    }
}
