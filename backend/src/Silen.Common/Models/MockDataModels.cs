namespace Silen.Common.Models;

/// <summary>
/// The behavior profiles the mock-data seeder can build a month of history from.
/// They are deliberately different so tier-gated features and analytics have
/// something realistic to look at: Advanced runs a heavier split with tighter
/// adherence and precise macro logging, Pro a simpler split with looser adherence
/// and sloppier logging.
///
/// The names are the contract between the console's profile picker, the service
/// layer's validation and the seeder's tier table - see database/seed/001 for the
/// plan codes each maps to (ADVANCED / PRO).
/// </summary>
public static class MockDataProfiles
{
    public const string Advanced = "Advanced";
    public const string Pro = "Pro";

    public static readonly IReadOnlyList<string> All = [Advanced, Pro];
}

/// <summary>
/// What one mock-data run produced, for the CLI tool's console output and the
/// console's confirmation toast. Counts are informational; the row it describes
/// is the user's, not the operator's.
/// </summary>
public sealed record MockDataSeedResult(
    Guid UserId,
    string Profile,
    string SplitName,
    int Days,
    int WorkoutsCompleted,
    int WorkoutsMissed,
    int MealsLogged,
    int HydrationEntries,
    int BodyweightEntries);
