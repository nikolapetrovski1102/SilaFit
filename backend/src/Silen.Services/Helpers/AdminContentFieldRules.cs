using Silen.Common.Exceptions;

namespace Silen.Services.Helpers;

/// <summary>
/// The closed sets the content columns accept, mirrored from the CHECK constraints
/// in database/schema (004, 012, 020, 022).
///
/// They are repeated here - rather than left to the constraint - because a
/// constraint violation surfaces as a SqlException and therefore a 500, whereas an
/// operator typing "arnold" into the category box deserves a 400 that says which
/// values exist. The constraints stay in place as the real guarantee; this is the
/// friendly side of the same rule. If one of these lists ever drifts, the database
/// still refuses the write.
/// </summary>
public static class AdminContentFieldRules
{
    public static readonly IReadOnlySet<string> MuscleGroups = new HashSet<string>(StringComparer.Ordinal)
    {
        "chest", "back", "legs", "shoulders", "arms", "core"
    };

    public static readonly IReadOnlySet<string> MealTypes = new HashSet<string>(StringComparer.Ordinal)
    {
        "Breakfast", "Lunch", "Dinner", "Snack"
    };

    public static readonly IReadOnlySet<string> SplitCategories = new HashSet<string>(StringComparer.Ordinal)
    {
        "PushPullLegs", "UpperLower", "FullBody", "ArnoldSplit",
        "PHUL", "PHAT", "BroSplit", "Circuit", "Powerlifting",
        "Calisthenics", "GluteFocus",
        // A self-built split shouldn't have to fit one of the curated archetypes
        // above - see 044_WorkoutSplitsUserOwnership.sql's CK_WorkoutSplits_Category widen.
        "Custom"
    };

    public static readonly IReadOnlySet<string> SplitLevels = new HashSet<string>(StringComparer.Ordinal)
    {
        "Beginner", "Intermediate", "Advanced"
    };

    public static readonly IReadOnlySet<string> RecommendedGoals = new HashSet<string>(StringComparer.Ordinal)
    {
        "BuildMuscle", "LoseFat", "MaintainActive"
    };

    /// <summary>
    /// Who an app user the split is not assigned to may be shown it. Mirrors the
    /// CK_WorkoutSplits_Visibility constraint added in schema 031.
    /// </summary>
    public static readonly IReadOnlySet<string> SplitVisibilities = new HashSet<string>(StringComparer.Ordinal)
    {
        "Private", "Public", "Shared"
    };

    /// <summary>Mirrors CK_DietPlans_PeriodType (schema 045) - display/filter metadata only.</summary>
    public static readonly IReadOnlySet<string> DietPlanPeriodTypes = new HashSet<string>(StringComparer.Ordinal)
    {
        "Weekly", "Monthly"
    };

    /// <summary>Same closed set as SplitVisibilities - DietPlans.Visibility mirrors
    /// WorkoutSplits.Visibility exactly (see CK_DietPlans_Visibility, schema 045).</summary>
    public static readonly IReadOnlySet<string> DietPlanVisibilities = SplitVisibilities;

    /// <summary>Rejects anything outside <paramref name="allowed"/>, naming the field and the alternatives.</summary>
    public static void ThrowIfUnknown(string? value, IReadOnlySet<string> allowed, string fieldName)
    {
        if (value is null || !allowed.Contains(value))
        {
            throw new ValidationException(
                $"Admin content write rejected an unknown {fieldName}: '{value}'.",
                $"'{value}' is not a valid {fieldName}. Expected one of: {string.Join(", ", allowed)}.");
        }
    }

    /// <summary>Same, for an optional field where empty/null is legitimate.</summary>
    public static void ThrowIfUnknownWhenSet(string? value, IReadOnlySet<string> allowed, string fieldName)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            ThrowIfUnknown(value, allowed, fieldName);
        }
    }
}
