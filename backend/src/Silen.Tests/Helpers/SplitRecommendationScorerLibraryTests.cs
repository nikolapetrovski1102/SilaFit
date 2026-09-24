using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

/// <summary>
/// End-to-end accuracy checks against the real curated library. The splits here
/// mirror the shipped 38-split import's actual metadata (category, level, goal,
/// days, equipment, source audience) so the recommender is exercised on the data
/// it will actually see, not only synthetic edge cases.
/// </summary>
public class SplitRecommendationScorerLibraryTests
{
    private static WorkoutSplitModel Split(
        string name,
        string category,
        string level,
        string goal,
        byte days,
        string? equipment = null,
        string? type = "Split",
        string? gender = "Male & Female",
        string? sourceCategories = null,
        short? min = null,
        short? max = null) => new()
    {
        SplitId = Guid.NewGuid(),
        Name = name,
        Category = category,
        Level = level,
        RecommendedGoal = goal,
        DurationDays = days,
        DaysPerWeek = days,
        IsSystemDefault = true,
        SortOrder = 1000,
        EquipmentRequired = equipment,
        WorkoutTypeLabel = type,
        TargetGender = gender,
        SourceCategoriesJson = sourceCategories,
        MinSessionMinutes = min,
        MaxSessionMinutes = max
    };

    private static readonly WorkoutSplitModel PplBeginners = Split(
        "3 Day Push/Pull/Legs (PPL) for Beginners", "PushPullLegs", "Beginner", "BuildMuscle", 3,
        "Barbell, Cables, Dumbbells, Machines", sourceCategories: "[\"Muscle Building\",\"Men\"]");

    private static readonly WorkoutSplitModel Phul = Split(
        "P.H.U.L. (Power Hypertrophy Upper Lower)", "PHUL", "Intermediate", "BuildMuscle", 4,
        "Barbell, Dumbbells, Machines", sourceCategories: "[\"Muscle Building\",\"Men\"]");

    private static readonly WorkoutSplitModel Dumbbell4 = Split(
        "Dumbbell Only Workout: 4 Day Upper/Lower", "UpperLower", "Beginner", "BuildMuscle", 4,
        "Bodyweight, Dumbbells", sourceCategories: "[\"Muscle Building\",\"Men\",\"At Home\"]");

    private static readonly WorkoutSplitModel Dumbbell5 = Split(
        "5 Day Dumbbell Only Workout", "BroSplit", "Intermediate", "BuildMuscle", 5,
        "Bodyweight, Dumbbells", sourceCategories: "[\"Muscle Building\",\"Men\",\"At Home\"]");

    private static readonly WorkoutSplitModel BodyGod = Split(
        "Body Like A God: Bodyweight Muscle Building Plan", "Calisthenics", "Beginner", "BuildMuscle", 4,
        "Bodyweight", "Full Body", sourceCategories: "[\"Muscle Building\",\"Men\",\"Bodyweight\",\"At Home\"]");

    private static readonly WorkoutSplitModel FatLoss40 = Split(
        "8-Week Fat Loss Program for Adults 40+", "FullBody", "Beginner", "LoseFat", 3,
        "Barbell, Cables, Dumbbells, Machines", "Full Body",
        sourceCategories: "[\"Women\",\"Fat Loss\",\"Men\",\"Beginner\"]");

    private static readonly WorkoutSplitModel Muscle40 = Split(
        "8-Week Muscle Building Program for Adults 40+", "BroSplit", "Beginner", "BuildMuscle", 4,
        "Barbell, Bodyweight, Cables, Dumbbells, Machines");

    private static readonly WorkoutSplitModel Lean40Women = Split(
        "10-Week Lean & Strong Program for Women 40+", "BroSplit", "Beginner", "LoseFat", 4,
        "Barbell, Bodyweight, Cables, Dumbbells, Machines, Other", gender: "Female",
        sourceCategories: "[\"Women\",\"Muscle Building\",\"Fat Loss\"]");

    private static readonly WorkoutSplitModel WomenUpperLower = Split(
        "10 Week Upper/Lower Workout Program for Women", "UpperLower", "Intermediate", "BuildMuscle", 4,
        "Barbell, Bodyweight, Cables, Dumbbells", gender: "Female",
        sourceCategories: "[\"Women\",\"Muscle Building\"]");

    private static readonly WorkoutSplitModel WomenDumbbell4 = Split(
        "4 Day Upper/Lower Women's Dumbbell Only Workout", "UpperLower", "Beginner", "BuildMuscle", 4,
        "Dumbbells", gender: "Female", sourceCategories: "[\"Women\"]");

    private static readonly WorkoutSplitModel WomenFatLoss = Split(
        "8 Week Beginner Fat Loss Workout for Women", "BroSplit", "Beginner", "LoseFat", 4,
        "Barbell, Bodyweight, Cables, Dumbbells, Exercise Ball, Machines", gender: "Female",
        sourceCategories: "[\"Women\",\"Fat Loss\",\"Beginner\"]");

    private static readonly WorkoutSplitModel Arms = Split(
        "Awesome Arms: 8 Weeks to Better Biceps and Triceps", "BroSplit", "Beginner", "BuildMuscle", 1,
        "Barbell, Cables, Dumbbells, EZ Bar", "Single Muscle Group", sourceCategories: "[\"Muscle Building\",\"Men\"]");

    private static readonly WorkoutSplitModel Deload = Split(
        "2-Week Deload Workout Program", "BroSplit", "Beginner", "MaintainActive", 4,
        "Barbell, Bodyweight, Cables, Dumbbells", sourceCategories: "[\"Women\",\"Men\"]");

    private static readonly WorkoutSplitModel Celebrity = Split(
        "5 Day Athletic Hypertrophy Split", "BroSplit", "Intermediate", "BuildMuscle", 5,
        "Barbell, Bodyweight, Cables, Dumbbells, EZ Bar, Machines", sourceCategories: "[\"Muscle Building\",\"Men\",\"Celebrity\"]");

    private static readonly WorkoutSplitModel[] Library =
    [
        PplBeginners, Phul, Dumbbell4, Dumbbell5, BodyGod, FatLoss40, Muscle40, Lean40Women,
        WomenUpperLower, WomenDumbbell4, WomenFatLoss, Arms, Deload, Celebrity
    ];

    private static string PickName(PersonFit fit, string goal)
    {
        var ranked = SplitRecommendationScorer.Rank(Library, fit, goal);
        Assert.NotEmpty(ranked);
        return ranked[0].Name;
    }

    [Fact]
    public void BodyweightMale_GetsTheBodyweightProgram_NotAGymProgram()
    {
        var fit = PersonFit.From(175, 75, 28, 4, 45, "Beginner", "Bodyweight", "Active", "Male");
        Assert.Equal(BodyGod.Name, PickName(fit, "BuildMuscle"));
    }

    [Fact]
    public void DumbbellMale_GetsTheDumbbellProgram_OverBodyweightOrGym()
    {
        var fit = PersonFit.From(175, 75, 28, 4, 45, "Beginner", "Dumbbells", "Active", "Male");
        Assert.Equal(Dumbbell4.Name, PickName(fit, "BuildMuscle"));
    }

    [Fact]
    public void BeginnerMaleThreeDayFullGym_GetsTheBeginnerPpl()
    {
        var fit = PersonFit.From(175, 75, 28, 3, 45, "Beginner", "FullGym", "Active", "Male");
        Assert.Equal(PplBeginners.Name, PickName(fit, "BuildMuscle"));
    }

    [Fact]
    public void MastersMaleFourDay_GetsTheFortyPlusProgram()
    {
        // A 52-year-old is safety-capped at Beginner, so PHUL (Intermediate) is out;
        // the 40+ muscle program should beat the general beginner PPL on age fit.
        var fit = PersonFit.From(175, 75, 52, 4, 45, "Beginner", "FullGym", "Active", "Male");
        Assert.Equal(Muscle40.Name, PickName(fit, "BuildMuscle"));
    }

    [Fact]
    public void BeginnerFemaleFourDay_GetsAWomenSpecificProgram()
    {
        var fit = PersonFit.From(165, 60, 28, 4, 45, "Beginner", "FullGym", "Active", "Female");
        var pick = PickName(fit, "BuildMuscle");
        Assert.Contains("Women", pick);
    }

    [Fact]
    public void MastersFemaleLoseFat_GetsAFortyPlusProgram()
    {
        // A dedicated 40+ fat-loss program is a better goal fit than a general one,
        // and both outrank the non-age-specific women's fat-loss program.
        var fit = PersonFit.From(165, 60, 52, 4, 45, "Beginner", "FullGym", "Active", "Female");
        Assert.Contains("40+", PickName(fit, "LoseFat"));
    }

    [Fact]
    public void SpecialisationAndUtility_AreNeverTheTopRecommendation()
    {
        var fit = PersonFit.From(175, 78, 30, 4, 60, "Intermediate", "FullGym", "Active", "Male");
        var ranked = SplitRecommendationScorer.Rank(Library, fit, "BuildMuscle");

        Assert.NotEqual(Arms.SplitId, ranked[0].SplitId);
        Assert.NotEqual(Deload.SplitId, ranked[0].SplitId);
        Assert.NotEqual(Celebrity.SplitId, ranked[0].SplitId);
        Assert.False(SplitRecommendationScorer.IsAutoAssignable(Arms));
        Assert.False(SplitRecommendationScorer.IsAutoAssignable(Deload));
        Assert.False(SplitRecommendationScorer.IsAutoAssignable(Celebrity));
    }

    [Fact]
    public void OppositeGenderPrograms_AreFilteredForTheOtherGender()
    {
        var male = PersonFit.From(175, 78, 30, 4, 60, "Intermediate", "FullGym", "Active", "Male");
        var female = PersonFit.From(165, 60, 30, 4, 60, "Intermediate", "FullGym", "Active", "Female");

        // The women-only programs are a mismatch for him and the men-tagged PPL is a
        // mismatch for her, so neither can be auto-assigned.
        Assert.True(SplitRecommendationScorer.IsAudienceMismatch(WomenUpperLower, male));
        Assert.True(SplitRecommendationScorer.IsAudienceMismatch(PplBeginners, female));
        Assert.False(SplitRecommendationScorer.IsAudienceMismatch(WomenUpperLower, female));
    }
}
