namespace Silen.Common.Models;

/// <summary>One row of dbo.UserAuthIdentities - which sign-in methods this account has linked.</summary>
public sealed class LinkedIdentityModel
{
    public string Provider { get; set; } = string.Empty;
    public string ExternalId { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>One dbo.HydrationLogs row - no "get everything" procedure existed
/// before usp_Account_Export needed one (only today's total did).</summary>
public sealed class HydrationEntryModel
{
    public Guid HydrationLogId { get; set; }
    public short AmountMl { get; set; }
    public DateTime LoggedAtUtc { get; set; }
}

/// <summary>One dbo.WorkoutSessions row, full history (existing models only ever
/// carry a subset of these columns together - Today/Completion/RangeSummary
/// each serve a narrower purpose than a full export row needs).</summary>
public sealed class WorkoutSessionHistoryModel
{
    public Guid WorkoutSessionId { get; set; }
    public DateTime ScheduledDateUtc { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime? StartedAtUtc { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
    public short? DurationMinutes { get; set; }
    public short? CaloriesEstimate { get; set; }
    public decimal? RpeScore { get; set; }
    public decimal? TonnageKg { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>One dbo.WorkoutSetLogs row, full history.</summary>
public sealed class WorkoutSetLogEntryModel
{
    public Guid WorkoutSetLogId { get; set; }
    public Guid WorkoutSessionId { get; set; }
    public Guid ExerciseId { get; set; }
    public byte SetNumber { get; set; }
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}

/// <summary>Everything usp_Account_Export returns, one section per property, in the
/// same order the procedure's result sets are read - the "download my data" payload.</summary>
public sealed class AccountExportModel
{
    public UserAccountModel Account { get; set; } = new();
    public List<LinkedIdentityModel> LinkedIdentities { get; set; } = [];
    public UserProfileModel? Profile { get; set; }
    public UserSettingsModel? Settings { get; set; }
    public UserNutritionTargetsModel? NutritionTargets { get; set; }
    public List<BodyweightEntryModel> BodyweightHistory { get; set; } = [];
    public List<HydrationEntryModel> HydrationHistory { get; set; } = [];
    public List<MealLogModel> MealLogs { get; set; } = [];
    public List<WorkoutSessionHistoryModel> WorkoutSessions { get; set; } = [];
    public List<WorkoutSetLogEntryModel> WorkoutSetLogs { get; set; } = [];
    public UserSubscriptionModel? Subscription { get; set; }
}

/// <summary>Confirmation returned to the app once the export has been emailed -
/// the export payload itself never reaches the client, only this receipt.</summary>
public sealed class AccountExportRequestResultModel
{
    public string Email { get; set; } = string.Empty;
}
