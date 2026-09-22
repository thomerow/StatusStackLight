using StatusStackLight.Relay.Data;
using StatusStackLight.Relay.Domain;

namespace StatusStackLight.Relay.Services;

/// <summary>
/// Drives the transitions no event triggers: Done falls back to Ready, crashed sessions are
/// forgotten, the warning flash ends. Replaces the straggler process (-Event Tick) of the
/// script's LAN mode.
///
/// A quarter second keeps the warning flash close to its set duration (1.2 s become
/// 1.2...1.45 s); a tick without a change costs a few comparisons and nothing else.
/// </summary>
public sealed class RelayTimerService(RelayEngine engine, ApiKeyService keys, ILogger<RelayTimerService> log)
    : BackgroundService
{
    private static readonly TimeSpan Interval   = TimeSpan.FromMilliseconds(250);
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
