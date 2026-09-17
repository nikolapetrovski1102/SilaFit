using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Ranks catalogue exercises for one person, using the two onboarding answers that
/// genuinely change what someone can do: the equipment they have access to and how
/// much training experience they have.
///
/// This is deliberately separate from <see cref="SplitRecommendationScorer"/>: that
/// one matches a whole program (using the split's declared EquipmentRequired), while
/// this matches a single exercise via its own EquipmentType. Equipment is treated as
/// a constraint rather than a preference here too - recommending a barbell movement
/// to someone who only has dumbbells is not a ranking nuance, it is unusable advice.
/// </summary>
public static class ExerciseRecommendationScorer
{
    private const int EquipmentFitPoints = 120;
    private const int EquipmentMismatchPenalty = 90;
    private const int EquipmentBlockPenalty = 220;
    private const int CompoundPoints = 60;
    private const int BeginnerCompoundBonus = 40;
    private const int AdvancedIsolationPoints = 25;

    // How much the first requested muscle group is favoured over the next one,
    // and so on down the ordered list. Deliberately below CompoundPoints: when a
    // day names several groups, the order they were named should break ties
    // within otherwise-equal picks, not outrank a better equipment/experience
    // match.
    private const int MuscleGroupPriorityPoints = 45;
    private const int MuscleGroupPriorityStep = 15;

    /// <summary>Orders <paramref name="exercises"/> best-first, stamping
    /// <see cref="ExerciseModel.MatchScore"/> and <see cref="ExerciseModel.MatchReason"/>
    /// on each, and returns at most <paramref name="limit"/> of them. When
    /// <paramref name="preferredMuscleGroups"/> is supplied, earlier groups in that
    /// ordered list win ties so a day focused on "Chest &amp; Triceps" presents
    /// chest first and arms after.</summary>
    public static List<ExerciseModel> Rank(
        IReadOnlyList<ExerciseModel> exercises, PersonFit fit, int limit,
        IReadOnlyList<string>? preferredMuscleGroups = null)
    {
        foreach (var exercise in exercises)
        {
            var (score, reason) = Score(exercise, fit);

            var priorityBonus = MuscleGroupPriorityBonus(preferredMuscleGroups, exercise.MuscleGroup);
            if (priorityBonus > 0)
            {
                score += priorityBonus;
                reason = reason is null
                    ? "Matches this day's focus"
                    : $"Matches this day's focus · {reason}";
            }

            exercise.MatchScore = score;
            exercise.MatchReason = reason;
        }

        return exercises
            .OrderByDescending(exercise => exercise.MatchScore)
            .ThenBy(exercise => exercise.Name, StringComparer.OrdinalIgnoreCase)
            .Take(limit)
            .ToList();
    }

    /// <summary>Position-weighted points for an exercise whose group appears in the
    /// requested ordered list, or zero when nothing was requested / the group
    /// wasn't one of them.</summary>
    private static int MuscleGroupPriorityBonus(
        IReadOnlyList<string>? preferredMuscleGroups, string muscleGroup)
    {
        if (preferredMuscleGroups is not { Count: > 0 })
        {
            return 0;
        }

        for (var index = 0; index < preferredMuscleGroups.Count; index++)
        {
            if (string.Equals(preferredMuscleGroups[index], muscleGroup, StringComparison.OrdinalIgnoreCase))
            {
                return Math.Max(0, MuscleGroupPriorityPoints - index * MuscleGroupPriorityStep);
            }
        }

        return 0;
    }

    private static (int Score, string? Reason) Score(ExerciseModel exercise, PersonFit fit)
    {
        var score = 0;
        var reasons = new List<string>();

        var equipment = fit.EquipmentAccess;
        var type = (exercise.EquipmentType ?? string.Empty).Trim().ToLowerInvariant();
        var needsFreeWeightsOrMachines = type is "barbell" or "machine" or "cable";
        var needsWeights = needsFreeWeightsOrMachines || type is "dumbbell" or "kettlebell";

        if (equipment is not null)
        {
            switch (equipment)
            {
                case "FullGym":
                    score += EquipmentFitPoints;
                    break;

                // Dumbbells-only: a barbell/cable/machine movement can't be done at all.
                case "Dumbbells" when needsFreeWeightsOrMachines:
                    score -= EquipmentMismatchPenalty;
                    break;

                case "Dumbbells" when !needsWeights || type == "dumbbell":
                    score += EquipmentFitPoints;
                    reasons.Add("Works with the dumbbells you train with");
                    break;

                // Bodyweight-only: anything needing added load is out of reach.
                case "Bodyweight" when needsWeights:
                    score -= EquipmentBlockPenalty;
                    break;

                case "Bodyweight":
                    score += EquipmentFitPoints;
                    reasons.Add("Needs no equipment");
                    break;
            }
        }

        // Beginners get the most return from compound movements and the least from
        // isolation work; advanced lifters can profitably spend volume on isolations.
        var level = fit.PreferredLevel;
        if (exercise.IsCompound)
        {
            if (level == "Beginner")
            {
                score += CompoundPoints + BeginnerCompoundBonus;
                reasons.Add("A compound movement well suited to a beginner");
            }
            else
            {
                score += CompoundPoints;
            }
        }
        else if (level == "Advanced")
        {
            score += AdvancedIsolationPoints;
        }

        // Every applicable signal is spelled out rather than only the first: a
        // beginner with dumbbells should hear both why it suits their level and
        // why it's actually doable with their kit.
        return (score, reasons.Count == 0 ? null : string.Join(" · ", reasons));
    }
}
