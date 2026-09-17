using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class ExerciseRecommendationScorerTests
{
    private static ExerciseModel Exercise(
        string name, string? equipment, bool compound, string muscleGroup = "chest") => new()
    {
        ExerciseId = Guid.NewGuid(),
        Name = name,
        MuscleGroup = muscleGroup,
        EquipmentType = equipment,
        IsCompound = compound
    };

    private static PersonFit Fit(string? equipment, string experience = "Intermediate") =>
        PersonFit.From(180m, 80m, 30, null, null, experience, equipment, null);

    private static int RankOf(List<ExerciseModel> ranked, string name) =>
        ranked.FindIndex(e => e.Name == name);

    [Fact]
    public void DumbbellsOnlyUser_SeesBarbellMovementRankedBelowDumbbellOne()
    {
        var exercises = new[]
        {
            Exercise("Barbell Bench Press", "Barbell", true),
            Exercise("Dumbbell Bench Press", "Dumbbell", true)
        };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("Dumbbells"), 10);

        Assert.True(RankOf(ranked, "Dumbbell Bench Press") < RankOf(ranked, "Barbell Bench Press"));
    }

    [Fact]
    public void BodyweightOnlyUser_SeesMachineMovementRankedLast()
    {
        var exercises = new[]
        {
            Exercise("Cable Fly", "Cable", false),
            Exercise("Push Up", "Bodyweight", true)
        };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("Bodyweight"), 10);

        Assert.Equal("Push Up", ranked[0].Name);
        Assert.True(RankOf(ranked, "Cable Fly") > RankOf(ranked, "Push Up"));
    }

    [Fact]
    public void FullGymUser_IsNotPenalisedForEquipment()
    {
        var exercises = new[] { Exercise("Barbell Squat", "Barbell", true, "legs") };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("FullGym"), 10);

        // FullGym fit (120) + compound bonus (60); no equipment penalty applied.
        Assert.Equal(180, ranked[0].MatchScore);
    }

    [Fact]
    public void Beginner_PrefersCompoundOverIsolation_AndIsToldWhy()
    {
        var exercises = new[]
        {
            Exercise("Dumbbell Bench Press", "Dumbbell", true),
            Exercise("Dumbbell Fly", "Dumbbell", false)
        };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("Dumbbells", "Beginner"), 10);

        Assert.Equal("Dumbbell Bench Press", ranked[0].Name);
        Assert.Contains("beginner", ranked[0].MatchReason, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void UnknownProfile_StillRanksWithoutThrowing()
    {
        var exercises = new[]
        {
            Exercise("Deadlift", "Barbell", true, "back"),
            Exercise("Plank", "Bodyweight", false, "core")
        };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, PersonFit.Unknown, 10);

        Assert.Equal(2, ranked.Count);
        Assert.All(ranked, e => Assert.NotNull(e.MatchScore));
    }

    [Fact]
    public void Rank_RespectsLimit_AndOrdersBestFirst()
    {
        var exercises = Enumerable.Range(0, 12)
            .Select(i => Exercise($"Exercise {i:00}", "Dumbbell", true))
            .ToList();

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("FullGym"), 5);

        Assert.Equal(5, ranked.Count);
        Assert.True(ranked[0].MatchScore >= ranked[^1].MatchScore);
    }

    [Fact]
    public void NoPreferredGroups_LeavesScoresAndReasonsUnchanged()
    {
        var exercises = new[] { Exercise("Barbell Squat", "Barbell", true, "legs") };

        var ranked = ExerciseRecommendationScorer.Rank(exercises, Fit("FullGym"), 10);

        // FullGym fit (120) + compound bonus (60); no day-focus bump or reason.
        Assert.Equal(180, ranked[0].MatchScore);
        Assert.Null(ranked[0].MatchReason);
    }

    [Fact]
    public void PreferredGroups_BreakTiesTowardTheNamedOrder()
    {
        var exercises = new[]
        {
            Exercise("Cable Fly", "Cable", false, "chest"),
            Exercise("Triceps Pushdown", "Cable", false, "arms")
        };

        var ranked = ExerciseRecommendationScorer.Rank(
            exercises, Fit("FullGym"), 10, ["chest", "arms"]);

        // Same equipment/experience score; chest was named first so it leads.
        Assert.Equal("Cable Fly", ranked[0].Name);
        Assert.Contains("Matches this day's focus", ranked[0].MatchReason);
    }

    [Fact]
    public void PreferredGroups_CannotOutrankABetterEquipmentMatch()
    {
        var exercises = new[]
        {
            // Second-choice group, but doable with the user's equipment.
            Exercise("Dumbbell Bench Press", "Dumbbell", true, "chest"),
            // First-choice group, but unusable with dumbbells only.
            Exercise("Barbell Row", "Barbell", true, "back")
        };

        var ranked = ExerciseRecommendationScorer.Rank(
            exercises, Fit("Dumbbells"), 10, ["back", "chest"]);

        Assert.True(RankOf(ranked, "Dumbbell Bench Press") < RankOf(ranked, "Barbell Row"));
    }
}
