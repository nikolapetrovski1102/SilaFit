using Silen.Common.Models;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Scores and ranks the split library against one user's onboarding profile, so
/// <see cref="Implementations.SplitService.GetAllAsync"/> can show the ranked
/// screen list whose first row is the "best for you" hero. Purely advisory: the
/// user always activates a split themselves.
///
/// <para><b>Why this is not a single weighted sum.</b> A weighted sum lets a
/// strong preference outvote a hard constraint: a goal-matched barbell program
/// could beat a doable dumbbell one for someone who only owns dumbbells. Accuracy
/// here means honouring the things that are objectively true about the person
/// before rewarding how well a program matches their taste.</para>
///
/// <para><b>Hard constraints (evaluated only when the matching answer exists).</b>
/// Ordered most to least important, and represented as high bits so they sort
/// lexicographically ahead of every soft signal:</para>
///  1. audience   - never surface an explicitly opposite-gender program while a
///                   unisex or matching one exists;
///  2. equipment  - never surface a program the person's kit cannot support
///                   (barbell/machine work for a bodyweight or dumbbell setup);
///  3. level      - safety first: never above the self-reported, safety-capped
///                   level while an at-or-below option exists;
///  4. schedule   - a program needing more days than the person has can never
///                   outrank one that fits;
///  5. session    - a program whose typical day runs long for the person's
///                   session answer is pushed down (not hidden).
///
/// <para><b>Soft fit signals</b> then order everything inside the same constraint
/// tier: exact goal, level proximity, equipment precision, category affinity,
/// session fit, daily-activity recovery fit, audience match, a masters age fit
/// (40+ programs), and curated order.</para>
///
/// <para><b>Non-programs.</b> Single-muscle-group, celebrity, warm-up, deload and
/// glute/arm/ab-specialisation entries stay browseable in <see cref="Rank"/> but
/// are penalised so a real weekly program is ranked first whenever one exists.</para>
///
/// <para>Every answer is optional, so legacy profiles that only answered
/// height/weight/age/goal rank exactly as before (identical score to the old
/// goal + level heuristic).</para>
/// </summary>
public static class SplitRecommendationScorer
{
    /* ------------------------------- soft fit weights ------------------------------- */

    private const int GoalMatchPoints = 500;
    private const int BestLevelPoints = 250;
    private const int AdjacentLevelPoints = 120;
    private const int CategoryAffinityPoints = 150;
    private const int SystemDefaultPoints = 30;
    private const int HighIntensityPenalty = 120;
    private const int BmiNudgePoints = 60;
    private const int EquipmentFitPoints = 100;
    private const int EquipmentMismatchPenalty = 220;
    private const int EquipmentBlockPenalty = 420;
    private const int SessionFitPoints = 90;
    private const int SessionTooLongPenalty = 140;
    private const int SessionToleranceMinutes = 15;
    private const int ActivityMovementPoints = 60;
    private const int ActivityRecoveryPenalty = 80;
    private const int AudienceMatchPoints = 160;
    private const int AudienceMismatchPenalty = 260;
    private const int GenderCategoryAffinityPoints = 90;
    private const int GenderCategoryPenalty = 60;

    /// <summary>A masters (45+) profile is nudged toward a program authored for
    /// 40+, which is written for their recovery needs. Sized to outrank the audience
    /// and session bonuses an otherwise-even general program enjoys, while staying
    /// below a goal match so it never overrides what the person actually asked for.</summary>
    private const int AgeAffinityPoints = 250;

    /// <summary>Applied in ranking (and gated in auto-assign) to content that is
    /// not a whole weekly program, so it never becomes the default plan.</summary>
    private const int UtilitySplitPenalty = 300;

    /* ---------------------------- hard-constraint bits ----------------------------- */

    // Each hard constraint contributes one bit above the soft-score range, so the
    // ordering is lexicographic: audience > equipment > level > schedule > session.
    // A split passing more (and higher) constraints always outranks one passing
    // fewer, whatever the soft signals say.
    private const int AudienceOkBit = 1 << 5;
    private const int EquipmentOkBit = 1 << 4;
    private const int LevelOkBit = 1 << 3;
    private const int ScheduleOkBit = 1 << 2;
    private const int SessionOkBit = 1 << 1;

    /// <summary>Larger than the most any soft signal can add, so a constraint bit
    /// always dominates the soft score it is packed above.</summary>
    private const int ScoreBase = 10_000;

    private static readonly string[] HighIntensityCategories =
        ["PHAT", "ArnoldSplit", "Powerlifting"];

    // Equipment vocabulary that means "you need a commercial gym".
    private static readonly string[] GymEquipmentTerms =
    [
        "barbell", "ez bar", "smith machine", "machine", "cable", "lat pulldown",
        "leg press", "leg extension", "leg curl", "hack squat", "pec deck",
        "preacher", "trap bar"
    ];

    // Category fallbacks for splits with no structured EquipmentRequired (hand-authored
    // or legacy rows).
    private static readonly string[] GymOnlyCategories = ["Powerlifting", "PHAT", "PHUL", "ArnoldSplit"];
    private static readonly string[] HomeFriendlyCategories =
        ["Calisthenics", "Circuit", "FullBody", "GluteFocus", "UpperLower"];

    // Content that is a utility rather than a weekly program. Body-part
    // specialisations are identified by their WorkoutTypeLabel instead, so a
    // legitimate GluteFocus program is not caught by a name match.
    private static readonly string[] NonProgramNameTerms =
        ["warm-up", "warm up", "deload", "abs", "ab & core"];

    /// <summary>
    /// Scores every split in place (<see cref="WorkoutSplitModel.MatchScore"/>/
    /// <see cref="WorkoutSplitModel.MatchReason"/>) and returns them best-first.
    /// </summary>
    public static List<WorkoutSplitModel> Rank(
        IReadOnlyList<WorkoutSplitModel> splits,
        PersonFit fit,
        string? goal)
    {
        for (var i = 0; i < splits.Count; i++)
        {
            var split = splits[i];
            split.MatchScore = (HardConstraintKey(split, fit) * ScoreBase) + FitScore(split, fit, goal);
            split.MatchReason = BuildReason(split, fit, goal);
        }

        // LINQ's stable ordering preserves database curation for exact ties, so a
        // large imported catalog cannot overpower real profile signals by list size.
        return splits.OrderByDescending(s => s.MatchScore).ToList();
    }

    public static string GoalLabel(string goal) => goal switch
    {
        "BuildMuscle" => "Build Muscle",
        "LoseFat" => "Lose Fat",
        "MaintainActive" => "Stay Active",
        _ => goal
    };

    public static string CategoryLabel(string category) => category switch
    {
        "PushPullLegs" => "Push · Pull · Legs",
        "UpperLower" => "Upper · Lower",
        "FullBody" => "Full Body",
        "ArnoldSplit" => "Arnold Split",
        "BroSplit" => "Bro Split",
        "GluteFocus" => "Glute & Core",
        _ => category
    };

    /* ----------------------------------- ranking ----------------------------------- */

    /// <summary>
    /// Packs the hard constraints into high bits (most important highest). A
    /// constraint is only considered when the answer exists, so a missing answer
    /// can never distort the ranking and legacy profiles score on fit alone.
    /// </summary>
    private static int HardConstraintKey(WorkoutSplitModel split, PersonFit fit)
    {
        var key = 0;
        if (fit.Gender is not null && !IsAudienceMismatch(split, fit))
        {
            key |= AudienceOkBit;
        }

        if (fit.EquipmentAccess is not null && IsEquipmentCompatible(split, fit))
        {
            key |= EquipmentOkBit;
        }

        if (fit.TrainingExperience is not null && IsLevelCompatible(split, fit))
        {
            key |= LevelOkBit;
        }

        if (fit.TrainingDaysPerWeek is not null && IsScheduleCompatible(split, fit))
        {
            key |= ScheduleOkBit;
        }

        if (fit.SessionDurationMinutes is not null && IsSessionCompatible(split, fit))
        {
            key |= SessionOkBit;
        }

        return key;
    }

    private static int FitScore(WorkoutSplitModel split, PersonFit fit, string? goal)
    {
        var score = 0;

        if (goal is not null && split.RecommendedGoal == goal)
        {
            score += GoalMatchPoints;
        }

        score += LevelScore(split.Level, fit.PreferredLevel);
        score += EquipmentPrecision(split, fit);
        score += SessionFit(split, fit.SessionDurationMinutes);
        score += ActivityFit(split.Category, fit.DailyActivityLevel);
        score += CategoryAffinity(split.Category, fit, goal);
        score += AudienceFit(split, fit.Gender);

        // The curated library marks its masters programs in the title ("... 40+").
        if (fit.AgeBand == "Masters" && split.Name.Contains("40+", StringComparison.Ordinal))
        {
            score += AgeAffinityPoints;
        }

        if (split.IsSystemDefault)
        {
            score += SystemDefaultPoints;
        }

        if (!IsAutoAssignable(split))
        {
            score -= UtilitySplitPenalty;
        }

        return score;
    }

    /* ------------------------------ hard constraints ------------------------------- */

    /// <summary>
    /// True when a split is a whole weekly program, as opposed to a body-part
    /// specialisation, celebrity routine or utility content (warm-ups, deloads).
    /// Those stay in the ranked library so they remain browseable, but <see cref="Rank"/>
    /// penalizes them so a real weekly program is favored as the top recommendation.
    /// </summary>
    public static bool IsAutoAssignable(WorkoutSplitModel split)
    {
        if (string.Equals(split.WorkoutTypeLabel, "Single Muscle Group", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (HasSourceCategory(split, "Celebrity"))
        {
            return false;
        }

        var name = split.Name.ToLowerInvariant();
        return !NonProgramNameTerms.Any(term => name.Contains(term, StringComparison.Ordinal));
    }

    /// <summary>True when a split's source categories include <paramref name="category"/>
    /// (case-insensitive). Absent or unparseable JSON has no categories.</summary>
    private static bool HasSourceCategory(WorkoutSplitModel split, string category)
    {
        if (string.IsNullOrWhiteSpace(split.SourceCategoriesJson))
        {
            return false;
        }

        try
        {
            var categories = JsonSerializer.Deserialize<string[]>(split.SourceCategoriesJson) ?? [];
            return categories.Any(value => value.Equals(category, StringComparison.OrdinalIgnoreCase));
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>
    /// True when the person's equipment can actually support the split. A bodyweight
    /// setup can only run splits whose required equipment is bodyweight (or nothing);
    /// dumbbells can run anything that doesn't need a commercial gym; a full gym can
    /// run everything. Splits with no structured <see cref="WorkoutSplitModel.EquipmentRequired"/>
    /// fall back to a category estimate.
    /// </summary>
    public static bool IsEquipmentCompatible(WorkoutSplitModel split, PersonFit fit)
    {
        if (string.IsNullOrWhiteSpace(fit.EquipmentAccess))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(split.EquipmentRequired))
        {
            var required = split.EquipmentRequired.ToLowerInvariant();
            return fit.EquipmentAccess switch
            {
                "FullGym" => true,
                "Dumbbells" => !RequiresGym(required),
                "Bodyweight" => !RequiresAnyEquipment(required),
                _ => true
            };
        }

        return EquipmentCompatibleByCategory(split.Category, fit.EquipmentAccess);
    }

    private static bool RequiresGym(string requiredEquipment) =>
        ContainsAny(requiredEquipment, GymEquipmentTerms);

    /// <summary>True when anything beyond bodyweight is required. "Bodyweight" alone
    /// is compatible; "Bodyweight, Dumbbells" is not.</summary>
    private static bool RequiresAnyEquipment(string requiredEquipment)
    {
        var stripped = requiredEquipment.Replace("bodyweight", string.Empty).Trim(' ', ',');
        return stripped.Length > 0;
    }

    private static bool EquipmentCompatibleByCategory(string category, string equipmentAccess) => equipmentAccess switch
    {
        "FullGym" => true,
        "Dumbbells" => !GymOnlyCategories.Contains(category),
        "Bodyweight" => HomeFriendlyCategories.Contains(category),
        _ => true
    };

    /// <summary>
    /// True when the split is at or below the level the person can handle.
    /// <see cref="PersonFit.PreferredLevel"/> already applies the teen/masters/obese
    /// safety ceiling, so an over-reaching self-assessment is capped.
    /// </summary>
    public static bool IsLevelCompatible(WorkoutSplitModel split, PersonFit fit) =>
        LevelRank(split.Level) <= LevelRank(fit.PreferredLevel);

    /// <summary>
    /// True when the person's week can accommodate the split: a real weekly cadence
    /// at or under the days they answered.
    /// </summary>
    public static bool IsScheduleCompatible(WorkoutSplitModel split, PersonFit fit)
    {
        var splitDays = WeeklyDays(split);
        return fit.TrainingDaysPerWeek is { } days
            && IsWeeklyCadence(splitDays)
            && splitDays <= days;
    }

    /// <summary>
    /// True when the split's typical day fits the session-length answer (with a
    /// small tolerance), or when that question wasn't answered.
    /// </summary>
    public static bool IsSessionCompatible(WorkoutSplitModel split, PersonFit fit) =>
        fit.SessionDurationMinutes is not { } minutes || TypicalMinutes(split) <= minutes + SessionToleranceMinutes;

    /* -------------------------------- split shape ---------------------------------- */

    /// <summary>The split's real weekly cadence: the imported DaysPerWeek when
    /// present, otherwise DurationDays (which for hand-authored splits is the
    /// days-per-week figure).</summary>
    private static int WeeklyDays(WorkoutSplitModel split) => split.DaysPerWeek ?? split.DurationDays;

    /// <summary>True when a split's DurationDays is a days-per-week figure (the
    /// onboarding answer is 1-7) rather than a total program length.</summary>
    private static bool IsWeeklyCadence(int splitDays) => splitDays is >= 1 and <= 7;

    /* -------------------------------- fit signals ---------------------------------- */

    /// <summary>
    /// How well a category plays to the equipment the person actually has, used as a
    /// soft preference inside the equipment-constraint tier. Incompatible splits get
    /// a graded penalty so the least-bad reaches the top when nothing is compatible.
    /// </summary>
    private static int EquipmentPrecision(WorkoutSplitModel split, PersonFit fit)
    {
        if (string.IsNullOrWhiteSpace(fit.EquipmentAccess))
        {
            return 0;
        }

        if (IsEquipmentCompatible(split, fit))
        {
            return EquipmentFitPoints;
        }

        return fit.EquipmentAccess switch
        {
            "Bodyweight" => -EquipmentBlockPenalty,
            "Dumbbells" => -EquipmentMismatchPenalty,
            _ => 0
        };
    }

    /// <summary>
    /// Fits the person's session-duration answer against the split's real average
    /// training-day length. A short-session lifter is nudged away from the longest
    /// protocols without being blocked from them.
    /// </summary>
    private static int SessionFit(WorkoutSplitModel split, int? sessionMinutes)
    {
        if (sessionMinutes is not { } minutes)
        {
            return 0;
        }

        var overflow = TypicalMinutes(split) - minutes;
        if (overflow <= 0)
        {
            return SessionFitPoints;
        }

        if (overflow <= SessionToleranceMinutes)
        {
            return SessionFitPoints / 2;
        }

        return -SessionTooLongPenalty - ((overflow - SessionToleranceMinutes) * 4);
    }

    /// <summary>The split's typical training-day length: the imported min/max range
    /// when present, otherwise the database's average, otherwise a category estimate.</summary>
    private static int TypicalMinutes(WorkoutSplitModel split)
    {
        if (split.MinSessionMinutes is { } minimum)
        {
            return (minimum + (split.MaxSessionMinutes ?? minimum)) / 2;
        }

        if (split.AvgSessionMinutes > 0)
        {
            return split.AvgSessionMinutes;
        }

        return TypicalMinutesByCategory(split.Category);
    }

    /// <summary>Fallback day length per category, mirroring the shipped library's
    /// `SplitDays.EstimatedMinutes` (35-55 minutes).</summary>
    private static int TypicalMinutesByCategory(string category) => category switch
    {
        "Powerlifting" or "PHUL" or "PushPullLegs" => 50,
        "UpperLower" => 45,
        "FullBody" or "GluteFocus" => 40,
        "ArnoldSplit" or "PHAT" or "BroSplit" => 55,
        "Circuit" or "Calisthenics" => 35,
        _ => 50
    };

    /// <summary>
    /// Daily activity is a recovery/movement signal, not a training-capacity one.
    /// Very active people get a light nudge away from maximum-volume blocks, and
    /// sedentary people toward steady movement work.
    /// </summary>
    private static int ActivityFit(string category, string? activity)
    {
        if (activity is null)
        {
            return 0;
        }

        var highVolume = HighIntensityCategories.Contains(category);

        return activity switch
        {
            "VeryActive" when highVolume => -ActivityRecoveryPenalty,
            "VeryActive" => 0,
            "Sedentary" when category is "Circuit" or "FullBody" => ActivityMovementPoints,
            "Sedentary" when highVolume => -ActivityRecoveryPenalty / 2,
            _ => 0
        };
    }

    private static int LevelScore(string splitLevel, string preferredLevel)
    {
        var distance = Math.Abs(LevelRank(splitLevel) - LevelRank(preferredLevel));
        return distance switch
        {
            0 => BestLevelPoints,
            1 => AdjacentLevelPoints,
            _ => 0
        };
    }

    private static int LevelRank(string level) => level switch
    {
        "Beginner" => 0,
        "Intermediate" => 1,
        "Advanced" => 2,
        _ => 1
    };

    private static int CategoryAffinity(string category, PersonFit fit, string? goal)
    {
        if (!fit.HasProfile)
        {
            return 0;
        }

        var points = 0;

        string[] preferred = goal switch
        {
            "LoseFat" => ["Circuit", "FullBody", "GluteFocus"],
            "BuildMuscle" => ["PushPullLegs", "ArnoldSplit", "PHUL", "PHAT", "BroSplit", "UpperLower"],
            "MaintainActive" => ["FullBody", "UpperLower", "Calisthenics", "Circuit"],
            _ => []
        };

        if (preferred.Contains(category))
        {
            points += CategoryAffinityPoints;
        }

        // A teen/masters/obese profile gets high-volume power protocols pushed
        // down rather than hidden - still browsable, just not recommended.
        if ((fit.AgeBand is "Teen" or "Masters" || fit.BmiCategory == "Obese") &&
            HighIntensityCategories.Contains(category))
        {
            points -= HighIntensityPenalty;
        }

        // At an overweight/obese BMI, steady burn work is a better starting point.
        if (fit.BmiCategory is "Overweight" or "Obese")
        {
            if (category is "Circuit" or "FullBody")
            {
                points += BmiNudgePoints;
            }
            else if (category == "Powerlifting")
            {
                points -= BmiNudgePoints;
            }
        }

        // Glute/lower-body-biased programming is sought out more by women and less
        // by men. Soft reorder on top of the explicit audience tag.
        if (category == "GluteFocus")
        {
            var gender = fit.Gender?.ToLowerInvariant();
            if (gender is "female" or "woman")
            {
                points += GenderCategoryAffinityPoints;
            }
            else if (gender is "male" or "man")
            {
                points -= GenderCategoryPenalty;
            }
        }

        return points;
    }

    /* ----------------------------------- audience ---------------------------------- */

    /// <summary>Who a program's source explicitly says it is for. Anything
    /// unrecognised (or "Other") is treated as unknown and stays open to everyone.</summary>
    private enum Audience
    {
        Unknown,
        Unisex,
        Women,
        Men
    }

    private static Audience AudienceOf(string? targetGender)
    {
        if (string.IsNullOrWhiteSpace(targetGender))
        {
            return Audience.Unknown;
        }

        var target = targetGender.ToLowerInvariant();
        var includesWomen = target.Contains("female") || target.Contains("women");
        var includesMen = Regex.IsMatch(target, @"\bmale\b|\bmen\b");

        if (includesWomen && includesMen)
        {
            return Audience.Unisex;
        }

        if (includesWomen)
        {
            return Audience.Women;
        }

        return includesMen ? Audience.Men : Audience.Unknown;
    }

    /// <summary>
    /// The audience a split is actually for. TargetGender wins when it names a single
    /// gender; when it is missing or the import's catch-all "Male &amp; Female", the
    /// source categories break the tie: a program categorised for women and not men is
    /// women's, and vice versa.
    /// </summary>
    private static Audience AudienceFor(WorkoutSplitModel split)
    {
        var explicitAudience = AudienceOf(split.TargetGender);
        if (explicitAudience is Audience.Women or Audience.Men)
        {
            return explicitAudience;
        }

        var (includesWomen, includesMen) = SourceCategoryGenders(split.SourceCategoriesJson);
        if (includesWomen && !includesMen)
        {
            return Audience.Women;
        }

        return includesMen && !includesWomen ? Audience.Men : explicitAudience;
    }

    /// <summary>Gender cues carried by a split's <c>SourceCategoriesJson</c>
    /// (e.g. ["Women","Fat Loss","Full Body"]). Absent or unparseable JSON has no cues.</summary>
    private static (bool IncludesWomen, bool IncludesMen) SourceCategoryGenders(string? sourceCategoriesJson)
    {
        if (string.IsNullOrWhiteSpace(sourceCategoriesJson))
        {
            return (false, false);
        }

        string[] categories;
        try
        {
            categories = JsonSerializer.Deserialize<string[]>(sourceCategoriesJson) ?? [];
        }
        catch (JsonException)
        {
            return (false, false);
        }

        return (categories.Any(IsWomenCategory), categories.Any(IsMenCategory));
    }

    // Substring for "women" so "Women"/"Women's" both count; the word boundary for
    // "men" keeps it from matching inside "women", and "male" is exact so it does
    // not match inside "female".
    private static bool IsWomenCategory(string category) =>
        category.Contains("women", StringComparison.OrdinalIgnoreCase) ||
        category.Equals("female", StringComparison.OrdinalIgnoreCase);

    private static bool IsMenCategory(string category) =>
        Regex.IsMatch(category, @"\bmen\b", RegexOptions.IgnoreCase) ||
        category.Equals("male", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// True only when the publisher explicitly tagged a program for the opposite of
    /// the person's gender. Unisex/untagged programs are never a mismatch, so they
    /// remain eligible for everyone.
    /// </summary>
    public static bool IsAudienceMismatch(WorkoutSplitModel split, PersonFit fit)
    {
        if (string.IsNullOrWhiteSpace(fit.Gender))
        {
            return false;
        }

        var gender = fit.Gender.ToLowerInvariant();
        return AudienceFor(split) switch
        {
            Audience.Women => gender is "male" or "man",
            Audience.Men => gender is "female" or "woman",
            _ => false
        };
    }

    private static int AudienceFit(WorkoutSplitModel split, string? profileGender)
    {
        if (string.IsNullOrWhiteSpace(profileGender))
        {
            return 0;
        }

        var gender = profileGender.ToLowerInvariant();
        return AudienceFor(split) switch
        {
            Audience.Women when gender is "female" or "woman" => AudienceMatchPoints,
            Audience.Women when gender is "male" or "man" => -AudienceMismatchPenalty,
            Audience.Men when gender is "male" or "man" => AudienceMatchPoints,
            Audience.Men when gender is "female" or "woman" => -AudienceMismatchPenalty,
            _ => 0
        };
    }

    /* ----------------------------------- reasons ----------------------------------- */

    /// <summary>
    /// Leads with whatever constraint or answer actually shaped the pick, so the
    /// explanation reflects the onboarding answers instead of always talking about
    /// the goal.
    /// </summary>
    private static string BuildReason(WorkoutSplitModel split, PersonFit fit, string? goal)
    {
        var parts = new List<string>();

        var days = fit.TrainingDaysPerWeek;
        var splitDays = WeeklyDays(split);
        var scheduleStated = days is not null && IsWeeklyCadence(splitDays);
        if (scheduleStated)
        {
            parts.Add(splitDays <= days
                ? $"Fits your {days}-day week"
                : $"{splitDays} days - just over your {days}-day week");
        }

        if (fit.EquipmentAccess is not null)
        {
            parts.Add(IsEquipmentCompatible(split, fit)
                ? EquipmentReason(split, fit.EquipmentAccess)
                : "Needs more equipment than you have");
        }

        if (AudienceFit(split, fit.Gender) == AudienceMatchPoints)
        {
            parts.Add("Designed for your profile");
        }

        if (goal is not null && split.RecommendedGoal == goal)
        {
            parts.Add($"Matched to your {GoalLabel(goal)} goal");
        }

        var levelled = fit.HasProfile && LevelScore(split.Level, fit.PreferredLevel) == BestLevelPoints;
        if (levelled)
        {
            // Only name the experience answer when it is what the level actually
            // reflects. A safety-capped profile (e.g. a teen who said Advanced but is
            // held at Beginner) would otherwise read as a contradiction.
            var experience = fit.TrainingExperience;
            parts.Add(experience is not null &&
                      string.Equals(experience, split.Level, StringComparison.OrdinalIgnoreCase)
                ? $"{split.Level} level suits your {experience.ToLowerInvariant()} experience"
                : $"{split.Level} level suits your profile");
        }
        else if (parts.Count == 0 && fit.HasProfile)
        {
            parts.Add("Fits your age and build");
        }

        if (parts.Count == 0 && split.IsSystemDefault)
        {
            parts.Add("Featured starter protocol");
        }
        else if (parts.Count == 0)
        {
            parts.Add($"{CategoryLabel(split.Category)} training");
        }

        // The schedule clause already states the day count; append it otherwise.
        if (!scheduleStated)
        {
            parts.Add($"{splitDays} days");
        }

        return string.Join(" · ", parts);
    }

    private static string EquipmentReason(WorkoutSplitModel split, string equipment) => equipment switch
    {
        "Bodyweight" when split.Category == "Calisthenics" => "Bodyweight-only, like you",
        "Bodyweight" => "Little to no equipment needed",
        "Dumbbells" => "Works with your dumbbells",
        "FullGym" => "Uses your full gym",
        _ => "Matches your equipment"
    };

    private static bool ContainsAny(string value, params string[] terms) =>
        terms.Any(term => value.Contains(term, StringComparison.Ordinal));
}
