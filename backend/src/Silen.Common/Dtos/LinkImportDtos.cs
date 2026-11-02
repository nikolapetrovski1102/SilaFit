namespace Silen.Common.Dtos;

/// <summary>A video link the user shared into the app from TikTok (or pasted).</summary>
public sealed class LinkImportRequest
{
    public string? Url { get; set; }
}

/// <summary>What the AI read out of a shared post: a workout (exercises matched to the
/// library) or a meal (ingredients in the same per-100 g shape as a photo scan), or neither.</summary>
public sealed class LinkImportResultDto
{
    /// <summary>"workout", "meal" or "other" (the post is neither - no scan was used).</summary>
    public string Kind { get; set; } = "other";

    public string Title { get; set; } = string.Empty;

    /// <summary>One short caveat from the model, or empty.</summary>
    public string Notes { get; set; } = string.Empty;

    public LinkImportSourceDto Source { get; set; } = new();
    public List<LinkImportExerciseDto> Exercises { get; set; } = [];

    /// <summary>Set when <see cref="Kind"/> is "meal". One serving's ingredients.</summary>
    public FoodScanResultDto? Meal { get; set; }

    public LinkImportQuotaDto Quota { get; set; } = new();
}

/// <summary>The post the result came from, credited in the app with a link back.</summary>
public sealed class LinkImportSourceDto
{
    public string Provider { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public string AuthorName { get; set; } = string.Empty;
    public string? ThumbnailUrl { get; set; }
}

public sealed class LinkImportExerciseDto
{
    /// <summary>The library exercise this matched, or null when the library has nothing close
    /// (the app then offers to pick one or add it as a custom exercise).</summary>
    public Guid? ExerciseId { get; set; }

    /// <summary>The library name when matched, otherwise the name as the post said it.</summary>
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public int Sets { get; set; }
    public int RepsLow { get; set; }
    public int RepsHigh { get; set; }
}

/// <summary>The caller's shared-link scan allowance.</summary>
public sealed class LinkImportQuotaDto
{
    /// <summary>"free", "pro" or "advanced".</summary>
    public string Tier { get; set; } = "free";

    public LinkImportKindQuotaDto Workout { get; set; } = new();
    public LinkImportKindQuotaDto Meal { get; set; } = new();

    /// <summary>Free tier only: trial scans left (any kind, never resets). Null on a paid tier.</summary>
    public int? TrialRemaining { get; set; }
    public int TrialLimit { get; set; }
}

public sealed class LinkImportKindQuotaDto
{
    /// <summary>False when the tier doesn't include this kind (Pro has no meal scans).</summary>
    public bool IsAvailable { get; set; }
    public int DailyLimit { get; set; }

    /// <summary>Scans of this kind left now - today's for a paid tier, the trial's for Free.</summary>
    public int Remaining { get; set; }
}
