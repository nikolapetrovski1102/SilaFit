namespace Silen.Common.Models;

public sealed class WorkoutSplitModel
{
    public Guid SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;
    public byte DurationDays { get; set; }
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }

    /// <summary>Who may see this split in the app: 'Public' (everyone), 'Shared'
    /// (assigned users only) or 'Private' (its owner only). The app-side list and
    /// detail procedures have already filtered on it, so every split returned to a
    /// user is one they are allowed to see.</summary>
    public string Visibility { get; set; } = "Public";

    /// <summary>The UserProfiles.Goal value ('BuildMuscle'/'LoseFat'/'MaintainActive') this split
    /// best serves, or null if it isn't goal-tagged. Set from the WorkoutSplits row.</summary>
    public string? RecommendedGoal { get; set; }

    /// <summary>Computed by SplitService from the caller's own profile goal, not a DB column -
    /// true when RecommendedGoal matches the authenticated user's onboarding goal.</summary>
    public bool MatchesGoal { get; set; }

    /// <summary>Computed by SplitService from the caller's profile (goal + age/BMI-derived level
    /// fit + category affinity), not a DB column. Higher is a better match.</summary>
    public int MatchScore { get; set; }

    /// <summary>Plain-language explanation of <see cref="MatchScore"/>, shown in the UI.</summary>
    public string? MatchReason { get; set; }

    /// <summary>Average training-day length from the split's days (DB aggregate, rest days
    /// excluded), used to fit the user's session-duration answer. 0 when the split has no days
    /// scheduled yet or the database hasn't been migrated to emit it.</summary>
    public int AvgSessionMinutes { get; set; }
    public byte? DaysPerWeek { get; set; }
    public short? ProgramDurationWeeks { get; set; }
    public short? MinSessionMinutes { get; set; }
    public short? MaxSessionMinutes { get; set; }
    public string? EquipmentRequired { get; set; }
    public string? TargetGender { get; set; }
    public string? WorkoutTypeLabel { get; set; }
    public string? SourceCategoriesJson { get; set; }

    /// <summary>Set from the WorkoutSplits row when the caller built this split themselves
    /// via the in-app builder (see 044_WorkoutSplitsUserOwnership.sql). Not serialized to the
    /// client directly - <see cref="IsEditableByMe"/> is what the API exposes.</summary>
    public Guid? OwnerUserId { get; set; }

    /// <summary>Computed by SplitService: true only when OwnerUserId matches the
    /// authenticated caller. Trainer-assigned and system splits are never editable,
    /// regardless of who is asking.</summary>
    public bool IsEditableByMe { get; set; }

    /// <summary>True when Silen.Tools.WeeklyPlanGeneration wrote this split rather than the
    /// user building it by hand (see 051_WeeklyAiPlans.sql).</summary>
    public bool IsAiGenerated { get; set; }

    /// <summary>Null while this AI-generated split is still eligible to be overwritten by
    /// next Sunday's run; set once the user taps "Keep this plan", after which it is
    /// permanent and the next run creates a fresh split instead. Always null for a
    /// non-AI-generated split.</summary>
    public DateTime? AiKeptAtUtc { get; set; }
}

public sealed class SplitDayModel
{
    public Guid SplitDayId { get; set; }
    public byte DayIndex { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? FocusLabel { get; set; }
    public short EstimatedMinutes { get; set; }
    public bool IsRestDay { get; set; }
}

public sealed class SplitDayExerciseModel
{
    public Guid SplitDayId { get; set; }

    /// <summary>Identity of this row within SplitDayExercises - needed by the
    /// in-app builder to address a specific exercise slot for edit/delete
    /// (ExerciseId alone is not unique per day: the same exercise can appear
    /// twice, e.g. warm-up and working sets).</summary>
    public Guid SplitDayExerciseId { get; set; }

    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;

    /// <summary>Coarse catalogue muscle group (chest/back/legs/shoulders/arms/core).
    /// Surfaced to the builder so it can suggest more of what a day already
    /// trains when the day's title is generic ("Push", "Day 1").</summary>
    public string MuscleGroup { get; set; } = string.Empty;

    public byte SortOrder { get; set; }
    public byte TargetSets { get; set; }
    public byte TargetRepsLow { get; set; }
    public byte TargetRepsHigh { get; set; }
}

public sealed class ActiveSplitModel
{
    public Guid UserId { get; set; }
    public Guid SplitId { get; set; }
    public DateTime ActivatedAtUtc { get; set; }
    public string? Name { get; set; }
    public byte? DurationDays { get; set; }

    /// <summary>True when this split was picked by the recommender rather than
    /// the user themselves - only a split still flagged this way is ever
    /// revisited by a later auto-assign re-check.</summary>
    public bool IsAutoAssigned { get; set; }
}

public sealed class ExerciseModel
{
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public bool IsCompound { get; set; }
    public string? DemoVideoUrl { get; set; }

    /// <summary>Set only by the suggestion read (<c>ExercisesService.SuggestAsync</c>):
    /// higher means a better fit for this person's equipment and experience level.
    /// Null on plain search results, so a client can tell the two apart.</summary>
    public int? MatchScore { get; set; }

    /// <summary>Short human-readable justification, shown beside a suggestion. Every
    /// applicable signal is included, joined with " · ", so a beginner with dumbbells
    /// is told both why it suits their level and why it's doable with their kit.
    /// Null when nothing specific stood out.</summary>
    public string? MatchReason { get; set; }
}
