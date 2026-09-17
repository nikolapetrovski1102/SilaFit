namespace Silen.Common.Options;

/// <summary>Tunables for the weekly AI split/diet-plan generation batch (see Silen.Tools.WeeklyPlanGeneration),
/// the weekly counterpart of <see cref="MonthlyReviewOptions"/>.</summary>
public sealed class WeeklyPlanGenerationOptions
{
    public const string SectionName = "WeeklyPlanGeneration";

    /// <summary>
    /// When false (or when Smtp:Host is unconfigured) the batch still generates and
    /// stores every plan but skips the email - useful for a dry run / manual backfill.
    /// </summary>
    public bool SendEmails { get; set; } = true;

    /// <summary>When false the batch still generates and stores every plan but skips the push.</summary>
    public bool SendPushNotifications { get; set; } = true;

    /// <summary>
    /// A user with fewer than this many tracked units (completed sessions + days with a
    /// meal logged) last week doesn't have enough real signal to personalize a new plan
    /// from - same bar as <c>AnalyticsService</c>'s weekly report gate.
    /// </summary>
    public int MinTrackedActivityUnits { get; set; } = 2;

    /// <summary>How many best-fit exercises are offered to the model as candidates for the
    /// new split - the JSON schema's exerciseId enum is built from exactly this set.</summary>
    public int ExerciseCandidatePoolSize { get; set; } = 60;

    /// <summary>How many best-fit meals per meal type (Breakfast/Lunch/Dinner/Snack) are
    /// offered to the model as candidates for the new diet plan.</summary>
    public int MealCandidatePoolSizePerType { get; set; } = 15;

    /// <summary>Training days/week used when the user's profile hasn't answered it.</summary>
    public int DefaultDaysPerWeek { get; set; } = 3;

    /// <summary>Session length (minutes) used when the user's profile hasn't answered it.</summary>
    public int DefaultSessionMinutes { get; set; } = 60;
}
