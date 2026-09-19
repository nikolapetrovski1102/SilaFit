using Silen.Common.Models;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Scores every split in the library against one user's profile so the app can
/// surface a personalized "best for you" pick and an ordered shortlist. Two
/// callers share this: <see cref="Implementations.SplitService.GetAllAsync"/>
/// (the screens) and <see cref="Implementations.SplitService.AutoAssignRecommendedAsync"/>
/// (the first-time default written at account creation), so the split
/// auto-selected is always the same one the user would have been shown.
///
/// <see cref="Implementations.SplitService.AutoAssignRecommendedAsync"/> re-checks
/// this on every profile save (not just account creation) until the user
/// activates a split for themselves, so a first-time pick made before the
/// capacity questions were answered gets revisited once they are.
///
/// Signals, ordered by how much they should shape the pick:
///  - experience/level  - the first hard gate, because safety comes before
///                          convenience: a split above the person's self-reported
///                          level (already capped by a safety ceiling for
///                          teen/masters/obese profiles, see <see cref="PersonFit"/>)
///                          is never recommended while an at-or-below option
///                          exists. It outranks the schedule gate when the two
///                          conflict, so a beginner is never handed an advanced
///                          block just because it fits the week.
///  - schedule fit       - the second hard gate. A split that needs more training
///                          days than the person answered can never outrank one
///                          that fits their week, no matter how well it matches
///                          their goal, level or equipment. The offsets on
///                          <see cref="LevelCompatiblePoints"/>/
///                          <see cref="ScheduleCompatiblePoints"/> are each larger
///                          than every soft signal combined.
///  - practical capacity - the session length, equipment and daily activity the
///                          person answered. These outweigh the goal tag, because
///                          a split the person cannot realistically follow (a
///                          barbell block with bodyweight only) is a worse
///                          recommendation than one that is slightly off their
///                          goal but actually doable.
///  - goal match         - the onboarding goal the split is tagged for
///  - level fit          - within the gate, the exact level still scores best
///  - category affinity  - the split categories that suit the goal, with
///                          high-volume/intensity protocols discounted for
///                          teen/masters/obese profiles
///  - curated order      - system-default flag + SortOrder as a stable
///                          tie-break, so guests/pre-onboarding users still get
///                          the existing curation order
///  - source audience    - gender is used only when the publisher explicitly
///                          marks a program for women or men; an explicit
///                          opposite-gender program is never auto-activated while
///                          a unisex or matching one exists (unisex stays open to
///                          everyone).
///
/// Every capacity signal is skipped when its answer is null, so legacy profiles
/// that only answered height/weight/age/goal rank exactly as before.
/// </summary>
public static class SplitRecommendationScorer
{
    private const int GoalMatchPoints = 500;
    private const int BestLevelPoints = 250;
    private const int AdjacentLevelPoints = 120;
    private const int CategoryAffinityPoints = 150;
    private const int SystemDefaultPoints = 30;
    private const int HighIntensityPenalty = 120;
    private const int BmiNudgePoints = 60;

    // Capacity signals. Schedule and equipment mismatches are deliberately large
    // enough to overcome GoalMatchPoints; session length and daily activity are
    // softer nudges that only reorder otherwise-close options.
    private const int ScheduleFitPoints = 180;
    private const int ScheduleUnderStep = 20;
    private const int ScheduleOverflowPenalty = 160;
    private const int ScheduleOverflowStep = 300;
    private const int EquipmentFitPoints = 100;
    private const int EquipmentMismatchPenalty = 220;
    private const int EquipmentBlockPenalty = 420;
    private const int SessionFitPoints = 90;
    private const int SessionTooLongPenalty = 140;
    private const int ActivityMovementPoints = 60;
    private const int ActivityRecoveryPenalty = 80;
    private const int AudienceMatchPoints = 160;
    private const int AudienceMismatchPenalty = 260;

    // Soft gender signal on a category whose training emphasis is traditionally
    // gendered (glute/lower-body work). It nudges an otherwise-close pick toward
    // the profile that usually seeks it and away from the other, on top of the
    // explicit source-audience tag. Deliberately softer than every hard gate so
    // it only reorders comparable options.
    private const int GenderCategoryAffinityPoints = 90;
    private const int GenderCategoryPenalty = 60;

    // The most every soft signal can add, and the step a hard gate must clear so
    // it can never be outvoted by goal/level/category noise.
    private const int SoftSignalCeiling =
        GoalMatchPoints + BestLevelPoints + AdjacentLevelPoints + CategoryAffinityPoints +
        BmiNudgePoints + SystemDefaultPoints + SessionFitPoints + ActivityMovementPoints +
        AudienceMatchPoints + EquipmentFitPoints + GenderCategoryAffinityPoints;
    private const int HardGateStep = SoftSignalCeiling + ScheduleFitPoints + 1;

    // Schedule compatibility: a split the person's week can accommodate outranks
    // one that cannot, whatever else it matches.
    private const int ScheduleCompatiblePoints = HardGateStep;

    // Experience/capability outranks schedule (safety before convenience), so a
    // beginner is never recommended an advanced block while a doable one exists.
    private const int LevelCompatiblePoints = HardGateStep * 2;

    private static readonly string[] HighIntensityCategories =
        ["PHAT", "ArnoldSplit", "Powerlifting"];

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
            split.MatchScore = Score(split, fit, goal);
            split.MatchReason = BuildReason(split, fit, goal);
        }

        // LINQ's stable ordering preserves database curation for exact ties.
        // Keeping that order outside MatchScore prevents a large imported
        // catalog from overpowering real profile signals merely by list size.
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

    private static int Score(WorkoutSplitModel split, PersonFit fit, string? goal)
    {
        var score = 0;

        // Hard gates first, in precedence order: capability (safety) before
        // convenience (schedule), both before any preference signal.
        score += LevelCompatibility(split, fit);
        score += ScheduleFit(split, fit);

        score += EquipmentFit(split, fit.EquipmentAccess);
        score += AudienceFit(split, fit.Gender);

        if (goal is not null && split.RecommendedGoal == goal)
        {
            score += GoalMatchPoints;
        }

        score += LevelScore(split.Level, fit.PreferredLevel);
        score += SessionFit(split, fit.SessionDurationMinutes);
        score += ActivityFit(split.Category, fit.DailyActivityLevel);
        score += CategoryAffinity(split.Category, fit, goal);

        if (split.IsSystemDefault)
        {
            score += SystemDefaultPoints;
        }

        return score;
    }

    /// <summary>
    /// Hard gate on the person's capability: a split above their self-reported
    /// (safety-capped) experience level is pushed below every at-or-below option.
    /// Skipped when the experience question wasn't answered, so legacy profiles
    /// keep the old soft <see cref="LevelScore"/> ordering.
    /// </summary>
    private static int LevelCompatibility(WorkoutSplitModel split, PersonFit fit) =>
        fit.TrainingExperience is not null && IsLevelCompatible(split, fit)
            ? LevelCompatiblePoints
            : 0;

    /// <summary>
    /// True when the split is at or below the level the person can handle.
    /// <see cref="PersonFit.PreferredLevel"/> already applies the teen/masters/
    /// obese safety ceiling, so an over-reaching self-assessment is capped.
    /// </summary>
    public static bool IsLevelCompatible(WorkoutSplitModel split, PersonFit fit) =>
        LevelRank(split.Level) <= LevelRank(fit.PreferredLevel);

    /// <summary>
    /// Compared with the days per week the person said they can train. Being at or
    /// under their ceiling is compatible and earns the dominating
    /// <see cref="ScheduleCompatiblePoints"/> offset (with a small bonus for
    /// leaving fewer days unused); going over costs more the further it
    /// overshoots, so an off-by-one stays a close call while a 6-day program on a
    /// 2-day week is effectively ruled out.
    ///
    /// Only a real weekly cadence is compared: imported programs sometimes store
    /// a total program length (e.g. 30) in DurationDays, which says nothing about
    /// how many days a week the person trains, so those get no schedule signal.
    /// </summary>
    private static int ScheduleFit(WorkoutSplitModel split, PersonFit fit)
    {
        var splitDays = WeeklyDays(split);
        if (fit.TrainingDaysPerWeek is not { } days || !IsWeeklyCadence(splitDays))
        {
            return 0;
        }

        var shortfall = splitDays - days;
        if (shortfall <= 0)
        {
            return ScheduleCompatiblePoints + ScheduleFitPoints + (shortfall * ScheduleUnderStep);
        }

        return -(ScheduleOverflowPenalty + ((shortfall - 1) * ScheduleOverflowStep));
    }

    /// <summary>
    /// True when the person's week can accommodate the split: a real weekly
    /// cadence that is at or under the days they answered. A missing answer or a
    /// DurationDays that isn't a weekly cadence can't be judged, so it is not
    /// "compatible" for the auto-assign gate but also isn't penalised.
    /// </summary>
    public static bool IsScheduleCompatible(WorkoutSplitModel split, PersonFit fit)
    {
        var splitDays = WeeklyDays(split);
        return fit.TrainingDaysPerWeek is { } days
            && IsWeeklyCadence(splitDays)
            && splitDays <= days;
    }

    /// <summary>
    /// Chooses the split to auto-activate, applying the profile's hard gates in
    /// precedence order, then the schedule fit:
    ///  1. experience/level - never above what the person can handle while an
    ///     at-or-below option exists (safety first);
    ///  2. source audience  - never an explicit opposite-gender program while a
    ///     unisex or matching one exists;
    ///  3. schedule         - the best-fitting week wins; when nothing fits, the
    ///     closest cadence (fewest days over it) is used, so a 1-day answer still
    ///     gets the lightest available option rather than an arbitrary goal match.
    /// Profiles that never answered the level/days questions keep the existing
    /// top-of-list behaviour.
    /// </summary>
    public static WorkoutSplitModel? PickForAutoAssign(IReadOnlyList<WorkoutSplitModel> ranked, PersonFit fit)
    {
        var candidates = ranked.AsEnumerable();

        // 1. Safety first: respect the self-reported, safety-capped level.
        if (fit.TrainingExperience is not null)
        {
            var atOrBelow = candidates.Where(s => IsLevelCompatible(s, fit)).ToList();
            if (atOrBelow.Count > 0)
            {
                candidates = atOrBelow;
            }
        }

        // 2. Respect the source audience (unisex/untagged stays eligible).
        var audienceSafe = candidates.Where(s => !IsAudienceMismatch(s, fit)).ToList();
        if (audienceSafe.Count > 0)
        {
            candidates = audienceSafe;
        }

        var pool = candidates.ToList();

        // 3. Fit the week. No answer means there is nothing to fit to.
        if (fit.TrainingDaysPerWeek is null)
        {
            return pool.FirstOrDefault();
        }

        var compatible = pool.FirstOrDefault(s => IsScheduleCompatible(s, fit));
        if (compatible is not null)
        {
            return compatible;
        }

        // Nothing fits: the shortest weekly cadence is the closest to their week.
        // LINQ's stable OrderBy keeps the ranked (goal/level/equipment) order for
        // exact ties. Splits with no weekly cadence can't be compared and are only
        // used when no comparable split exists at all.
        var comparable = pool.Where(s => IsWeeklyCadence(WeeklyDays(s))).ToList();
        return comparable.Count == 0
            ? pool.FirstOrDefault()
            : comparable.OrderBy(WeeklyDays).First();
    }

    /// <summary>The split's real weekly cadence: the imported DaysPerWeek when
    /// present, otherwise DurationDays (which for hand-authored splits is the
    /// days-per-week figure).</summary>
    private static int WeeklyDays(WorkoutSplitModel split) => split.DaysPerWeek ?? split.DurationDays;

    /// <summary>True when a split's DurationDays is a days-per-week figure (the
    /// onboarding answer is 1-7) rather than a program length.</summary>
    private static bool IsWeeklyCadence(int splitDays) => splitDays is >= 1 and <= 7;

    /// <summary>
    /// How well a category plays to the equipment the person actually has. A
    /// bodyweight or dumbbell setup is a real constraint, not a preference: a
    /// barbell power block or a machine-heavy PHAT week simply isn't followable
    /// at home, so those categories are pushed below anything feasible.
    /// </summary>
    private static int EquipmentFit(WorkoutSplitModel split, string? equipment)
    {
        if (equipment is null)
        {
            return 0;
        }

        if (!string.IsNullOrWhiteSpace(split.EquipmentRequired))
        {
            var required = split.EquipmentRequired.ToLowerInvariant();
            var needsGym = ContainsAny(required, "barbell", "machine", "cable", "smith machine", "ez bar");
            var needsWeights = needsGym || ContainsAny(required, "dumbbell", "kettlebell", "bands", "band");
            return equipment switch
            {
                "FullGym" => EquipmentFitPoints,
                "Dumbbells" when needsGym => -EquipmentMismatchPenalty,
                "Dumbbells" when !needsWeights || required.Contains("dumbbell") => EquipmentFitPoints,
                "Bodyweight" when needsWeights => -EquipmentBlockPenalty,
                "Bodyweight" => EquipmentBlockPenalty,
                _ => 0
            };
        }

        return EquipmentFitByCategory(split.Category, equipment);
    }

    private static int EquipmentFitByCategory(string category, string? equipment) => equipment switch
    {
        "FullGym" => category switch
        {
            "Calisthenics" => -EquipmentFitPoints,
            "FullBody" or "Circuit" or "GluteFocus" => EquipmentFitPoints - 30,
            _ => EquipmentFitPoints
        },
        "Dumbbells" => category switch
        {
            "Powerlifting" => -EquipmentBlockPenalty,
            "PHAT" or "PHUL" or "ArnoldSplit" => -EquipmentMismatchPenalty,
            "BroSplit" or "PushPullLegs" => -80,
            "Calisthenics" => -60,
            _ => EquipmentFitPoints
        },
        "Bodyweight" => category switch
        {
            "Calisthenics" => EquipmentBlockPenalty,
            "Circuit" => EquipmentMismatchPenalty + 100,
            "FullBody" => EquipmentMismatchPenalty,
            "UpperLower" or "GluteFocus" => 40,
            "PushPullLegs" => -260,
            "BroSplit" => -360,
            "ArnoldSplit" or "PHUL" => -EquipmentBlockPenalty,
            "PHAT" or "Powerlifting" => -EquipmentBlockPenalty - 100,
            _ => 0
        },
        _ => 0
    };

    private static bool ContainsAny(string value, params string[] terms) =>
        terms.Any(term => value.Contains(term, StringComparison.Ordinal));

    /// <summary>Who a program's source explicitly says it is for. Anything
    /// unrecognised (or "Other") is treated as <see cref="Audience.Unknown"/> and
    /// stays open to every gender.</summary>
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
    /// The audience a split is actually for. <see cref="WorkoutSplitModel.TargetGender"/>
    /// wins when it names a single gender; when it is missing or the import's
    /// catch-all "Male &amp; Female" (<see cref="Audience.Unisex"/>), the source
    /// categories break the tie: a program categorised for women and not men is
    /// women's, and vice versa. Without that fallback the imported women's
    /// programs the scraper blanket-tagged "Male &amp; Female" stayed eligible to
    /// men - see database/seed/007_TagSplitAudience.sql, which re-tags the stored
    /// rows the same way.
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
    /// True only when the publisher explicitly tagged a program for the opposite
    /// of the person's gender. Unisex/untagged programs are never a mismatch, so
    /// they remain eligible for everyone.
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

    /// <summary>
    /// Fits the person's session-duration answer against the split's real average
    /// training-day length (see <see cref="WorkoutSplitModel.AvgSessionMinutes"/>).
    /// It is a soft signal: a short-session lifter is nudged away from the
    /// longest protocols without being blocked from them. When the database
    /// hasn't been migrated to emit the average, a category-level estimate from
    /// the shipped library stands in.
    /// </summary>
    private static int SessionFit(WorkoutSplitModel split, int? sessionMinutes)
    {
        if (sessionMinutes is not { } minutes)
        {
            return 0;
        }

        var typicalMinutes = split.MinSessionMinutes is { } minimum
            ? (minimum + (split.MaxSessionMinutes ?? minimum)) / 2
            : split.AvgSessionMinutes > 0
                ? split.AvgSessionMinutes
                : TypicalMinutes(split.Category);

        var overflow = typicalMinutes - minutes;
        if (overflow <= 0)
        {
            return SessionFitPoints;
        }

        if (overflow <= 15)
        {
            return SessionFitPoints / 2;
        }

        return -SessionTooLongPenalty - ((overflow - 15) * 4);
    }

    /// <summary>Fallback day length per category, mirroring the shipped library's
    /// `SplitDays.EstimatedMinutes` (35-55 minutes) for databases that predate the
    /// `AvgSessionMinutes` aggregate.</summary>
    private static int TypicalMinutes(string category) => category switch
    {
        "Powerlifting" or "PHUL" or "PushPullLegs" => 50,
        "UpperLower" => 45,
        "FullBody" or "GluteFocus" => 40,
        "ArnoldSplit" or "PHAT" or "BroSplit" => 55,
        "Circuit" or "Calisthenics" => 35,
        _ => 50
    };

    /// <summary>
    /// Daily activity is a recovery/movement signal, not a training-capacity one
    /// (it already sets the calorie target in <see cref="Implementations.MealPlanningService"/>).
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

        // At an overweight/obese BMI, steady burn work is a better starting
        // point than a max-effort strength block.
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

        // Glute/lower-body-biased programming is sought out more by women and
        // less by men. This is a soft reorder on top of the explicit audience
        // tag, so it makes male and female picks differ even when the library
        // has no gender-tagged program for either. Every other category and
        // every profile without a gender answer is unaffected.
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

    /// <summary>
    /// Leads with whatever capacity answer actually shaped the pick, so the
    /// explanation reflects the new onboarding answers instead of always talking
    /// about the goal.
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

        if (AudienceFit(split, fit.Gender) == AudienceMatchPoints)
        {
            parts.Add("Designed for your profile");
        }

        if (fit.EquipmentAccess is { } equipment)
        {
            parts.Add(equipment switch
            {
                "Bodyweight" when split.Category == "Calisthenics" => "Bodyweight-only, like you",
                "Bodyweight" => "Little to no equipment needed",
                "Dumbbells" => "Works with your dumbbells",
                "FullGym" => "Uses your full gym",
                _ => "Matches your equipment"
            });
        }

        if (goal is not null && split.RecommendedGoal == goal)
        {
            parts.Add($"Matched to your {GoalLabel(goal)} goal");
        }

        var levelled = fit.HasProfile && LevelScore(split.Level, fit.PreferredLevel) == BestLevelPoints;
        if (levelled)
        {
            // Only name the experience answer when it is what the level actually
            // reflects. A safety-capped profile (e.g. a teen who said Advanced
            // but is held at Beginner) would otherwise read as a contradiction.
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

        // The schedule clause already states the day count; append it otherwise
        // (no answer, or a DurationDays that isn't a weekly cadence).
        if (!scheduleStated)
        {
            parts.Add($"{splitDays} days");
        }

        return string.Join(" · ", parts);
    }
}
