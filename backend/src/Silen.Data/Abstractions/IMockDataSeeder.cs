using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Generates a realistic month of history - workouts, meals, hydration and
/// bodyweight - for a user so the Today dashboard, Progress heatmap and monthly
/// overview have something worth looking at instead of empty states.
///
/// This is the same generator behind the standalone Silen.Tools.SeedMockData CLI,
/// lifted into the Data layer so the admin console can run it for one existing
/// user without a second copy drifting. It writes straight to the tables rather
/// than through the app's own stored procedures wherever a procedure would stamp
/// LoggedAtUtc/ActivatedAtUtc as SYSUTCDATETIME() - correct for a live request
/// "right now", but this needs to backdate entries across the last N days.
/// Encrypted columns are still encrypted exactly the way the app does it, so
/// everything reads back through the real API without special-casing.
/// </summary>
public interface IMockDataSeeder
{
    /// <summary>The profile names this seeder understands - see <see cref="MockDataProfiles"/>.</summary>
    IReadOnlyList<string> Profiles { get; }

    /// <summary>
    /// Replaces the user's existing logs with a generated month ending today, makes
    /// them an active yearly subscriber on the profile's plan, and puts the
    /// profile's split on them. Returns null when the user id does not exist.
    ///
    /// Pass an <paramref name="actor"/> to write an audit row for the run; the CLI
    /// tool, which runs outside any operator session, passes null.
    /// </summary>
    Task<MockDataSeedResult?> SeedUserAsync(
        Guid userId,
        string profile,
        int days,
        int? seed,
        AdminActorModel? actor = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Resolves (creating if needed) the guest account for a device id and seeds
    /// it - the CLI tool's entry point.
    /// </summary>
    Task<MockDataSeedResult> SeedDeviceAsync(
        string deviceId,
        string profile,
        int days,
        int? seed,
        CancellationToken cancellationToken = default);
}
