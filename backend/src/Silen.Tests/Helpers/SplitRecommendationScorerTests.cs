using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class SplitRecommendationScorerTests
{
    private static WorkoutSplitModel Split(
        string name,
        string category,
        string level,
        byte durationDays,
        string? recommendedGoal,
        bool isSystemDefault = false,
        int avgSessionMinutes = 0,
        byte? daysPerWeek = null,
        string? equipmentRequired = null,
        string? targetGender = null,
        short? minSessionMinutes = null,
        short? maxSessionMinutes = null,
        string? sourceCategoriesJson = null) => new()
    {
        SplitId = Guid.NewGuid(),
        Name = name,
        Category = category,
        Level = level,
        DurationDays = durationDays,
        RecommendedGoal = recommendedGoal,
        IsSystemDefault = isSystemDefault,
        AvgSessionMinutes = avgSessionMinutes,
        DaysPerWeek = daysPerWeek,
        EquipmentRequired = equipmentRequired,
        TargetGender = targetGender,
        MinSessionMinutes = minSessionMinutes,
        MaxSessionMinutes = maxSessionMinutes,
        SourceCategoriesJson = sourceCategoriesJson
    };

    [Fact]
    public void Rank_PrefersDoableScheduleAndEquipment_OverGoalOnlyMatch()
    {
        // 3 days/week, dumbbells only, beginner, sedentary - can't realistically
        // run a 6-day PPL block even though it's tagged for the same goal.
        var fit = PersonFit.From(170, 75, 25, trainingDaysPerWeek: 3, sessionDurationMinutes: 45,
            trainingExperience: "Beginner", equipmentAccess: "Dumbbells", dailyActivityLevel: "Sedentary");

        var fullBody = Split("Full Body 3-Day", "FullBody", "Beginner", 3, "BuildMuscle", isSystemDefault: true);
        var pushPullLegs = Split("PPL 6-Day", "PushPullLegs", "Intermediate", 6, "BuildMuscle");

        var ranked = SplitRecommendationScorer.Rank([pushPullLegs, fullBody], fit, "BuildMuscle");

        Assert.Equal(fullBody.SplitId, ranked[0].SplitId);
        Assert.True(ranked[0].MatchScore > ranked[1].MatchScore);
    }

    [Fact]
    public void Rank_DemotesHighIntensitySplits_ForObeseMastersProfile_WithoutHidingThem()
    {
        // Obese + Masters + bodyweight-only + Lose Fat: the safety cap should push
        // Powerlifting well below Circuit, but both must still be returned.
        var fit = PersonFit.From(170, 95, 52, trainingDaysPerWeek: 3, sessionDurationMinutes: null,
            trainingExperience: "Advanced", equipmentAccess: "Bodyweight", dailyActivityLevel: "Sedentary");

        var circuit = Split("Circuit 3-Day", "Circuit", "Beginner", 3, "LoseFat", isSystemDefault: true);
        var powerlifting = Split("Powerlifting 4-Day", "Powerlifting", "Advanced", 4, "BuildMuscle");

        var ranked = SplitRecommendationScorer.Rank([circuit, powerlifting], fit, "LoseFat");

        Assert.Equal(2, ranked.Count);
        Assert.Equal(circuit.SplitId, ranked[0].SplitId);
        Assert.True(ranked[0].MatchScore > ranked[1].MatchScore);
        // Safety-capped preferred level is Beginner regardless of the "Advanced" claim.
        Assert.Equal("Beginner", fit.PreferredLevel);
    }

    [Fact]
    public void Rank_MissingCapacityAnswers_SkipsScheduleAndEquipmentSignals()
    {
        // Legacy profile: only goal is known, no training-preference answers.
        // A goal-matched 6-day split should not be penalized for schedule/equipment
        // it was never told about.
        var fit = PersonFit.Unknown;

        var sixDay = Split("PPL 6-Day", "PushPullLegs", "Intermediate", 6, "BuildMuscle");
        var ranked = SplitRecommendationScorer.Rank([sixDay], fit, "BuildMuscle");

        // Goal match (500) + level adjacency (Intermediate vs default Beginner = 120).
        // No schedule/equipment/category signal since
        // HasProfile is false and no capacity answers were given.
        Assert.Equal(500 + 120, ranked[0].MatchScore);
    }

    [Fact]
    public void Rank_IsStableOnExactTies_PreservingInputOrder()
    {
        var fit = PersonFit.Unknown;
        var first = Split("A", "FullBody", "Beginner", 3, null);
        var second = Split("B", "FullBody", "Beginner", 3, null);

        var ranked = SplitRecommendationScorer.Rank([first, second], fit, null);

        Assert.Equal(first.SplitId, ranked[0].SplitId);
        Assert.Equal(second.SplitId, ranked[1].SplitId);
    }

    [Fact]
    public void Rank_UsesSourceAudience_ForWomenSpecificPrograms()
    {
        var fit = PersonFit.From(168, 65, 28, 4, 60, "Intermediate", "FullGym", "Active", "Female");
        var general = Split("General", "UpperLower", "Intermediate", 4, "BuildMuscle", targetGender: "Male & Female");
        var women = Split("Women", "UpperLower", "Intermediate", 4, "BuildMuscle", targetGender: "Female");

        var ranked = SplitRecommendationScorer.Rank([general, women], fit, "BuildMuscle");

        Assert.Equal(women.SplitId, ranked[0].SplitId);
        Assert.Contains("Designed for your profile", ranked[0].MatchReason);
    }

    [Fact]
    public void Rank_UsesImportedScheduleEquipmentAndSessionMetadata()
    {
        var fit = PersonFit.From(175, 75, 30, 3, 45, "Intermediate", "Dumbbells", "Active");
        var feasible = Split("Feasible", "BroSplit", "Intermediate", 6, "BuildMuscle",
            daysPerWeek: 3, equipmentRequired: "Dumbbells", minSessionMinutes: 30, maxSessionMinutes: 45);
        var blocked = Split("Blocked", "BroSplit", "Intermediate", 3, "BuildMuscle",
            daysPerWeek: 5, equipmentRequired: "Barbell, Cables, Machines", minSessionMinutes: 60, maxSessionMinutes: 75);

        var ranked = SplitRecommendationScorer.Rank([blocked, feasible], fit, "BuildMuscle");

        Assert.Equal(feasible.SplitId, ranked[0].SplitId);
    }

    [Fact]
    public void Rank_ScheduleCompatibleSplit_OutranksGoalMatchedOverScheduleSplit()
    {
        // Reported bug: a 2-day/week user must not be handed a 4-day block just
        // because it matches their goal, level and category.
        var fit = PersonFit.From(170, 75, 30, 2, 45, "Intermediate", "FullGym", "Active");
        var maintenance2 = Split("2-Day Maintenance Full Body", "FullBody", "Beginner", 2, "MaintainActive", isSystemDefault: true);
        var phul4 = Split("PHUL Power Hypertrophy", "PHUL", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([phul4, maintenance2], fit, "BuildMuscle");

        Assert.Equal(maintenance2.SplitId, ranked[0].SplitId);
        Assert.True(ranked[0].MatchScore > ranked[1].MatchScore);
    }

    [Fact]
    public void PickForAutoAssign_PrefersScheduleCompatibleSplit()
    {
        var fit = PersonFit.From(170, 75, 30, 2, 45, "Intermediate", "FullGym", "Active");
        var maintenance2 = Split("2-Day Maintenance Full Body", "FullBody", "Beginner", 2, "MaintainActive", isSystemDefault: true);
        var phul4 = Split("PHUL Power Hypertrophy", "PHUL", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([phul4, maintenance2], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(maintenance2.SplitId, pick!.SplitId);
    }

    [Fact]
    public void PickForAutoAssign_NoCompatibleSplit_FallsBackToClosestCadence()
    {
        // A 1-day answer has no exact match: the two-day split is the lightest
        // over-schedule option and must beat the goal-matched four-day block.
        var fit = PersonFit.From(170, 75, 30, 1, 45, "Intermediate", "FullGym", "Active");
        var twoDay = Split("Two Day", "FullBody", "Beginner", 2, "MaintainActive", isSystemDefault: true);
        var fourDay = Split("Four Day PHUL", "PHUL", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([fourDay, twoDay], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(twoDay.SplitId, pick!.SplitId);
    }

    [Fact]
    public void PickForAutoAssign_NoDaysAnswer_ReturnsTopRankedSplit()
    {
        var fit = PersonFit.Unknown;
        var featured = Split("Featured", "FullBody", "Beginner", 3, "BuildMuscle", isSystemDefault: true);
        var other = Split("Other", "FullBody", "Beginner", 3, "BuildMuscle");

        var ranked = SplitRecommendationScorer.Rank([other, featured], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(ranked[0].SplitId, pick!.SplitId);
    }

    [Fact]
    public void Rank_PrefersDoableLevel_OverGoalMatchedAdvancedSplit()
    {
        // A beginner must never out-rank a doable beginner split with an advanced
        // block, even when the advanced block matches their goal.
        var fit = PersonFit.From(170, 70, 30, 4, 60, "Beginner", "FullGym", "Active");
        var advanced = Split("Powerlifting Strength Block", "Powerlifting", "Advanced", 4, "BuildMuscle", isSystemDefault: true);
        var beginner = Split("Upper / Lower Split", "UpperLower", "Beginner", 4, "MaintainActive", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([advanced, beginner], fit, "BuildMuscle");

        Assert.Equal(beginner.SplitId, ranked[0].SplitId);
        Assert.True(ranked[0].MatchScore > ranked[1].MatchScore);
    }

    [Fact]
    public void PickForAutoAssign_NeverPicksAboveSelfReportedLevel()
    {
        var fit = PersonFit.From(170, 70, 30, 4, 60, "Beginner", "FullGym", "Active");
        var advanced = Split("Advanced PHAT", "PHAT", "Advanced", 4, "BuildMuscle", isSystemDefault: true);
        var beginner = Split("Beginner Full Body", "FullBody", "Beginner", 4, "MaintainActive", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([advanced, beginner], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(beginner.SplitId, pick!.SplitId);
    }

    [Fact]
    public void Rank_MissingExperience_DoesNotGateByLevel()
    {
        // Legacy profile with no experience answer keeps the old soft ordering:
        // the goal-matched advanced split can still win.
        var legacy = PersonFit.From(170, 70, 30, 4, 60, null, "FullGym", "Active");
        var advanced = Split("Advanced PHUL", "PHUL", "Advanced", 4, "BuildMuscle", isSystemDefault: true);
        var beginner = Split("Beginner Full Body", "FullBody", "Beginner", 4, "MaintainActive", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([beginner, advanced], legacy, "BuildMuscle");

        Assert.Equal(advanced.SplitId, ranked[0].SplitId);
    }

    [Fact]
    public void PickForAutoAssign_NeverPicksOppositeGenderProgram()
    {
        // The women's program is the better goal match, but a male user must never
        // see it as his top pick: the audience constraint outranks the goal match,
        // in the ranked list and in the auto-assign pick alike.
        var fit = PersonFit.From(170, 70, 30, 3, 60, "Beginner", "FullGym", "Active", "Male");
        var womenOnly = Split("Women's Program", "FullBody", "Beginner", 3, "BuildMuscle",
            isSystemDefault: true, targetGender: "Female");
        var unisex = Split("Unisex Program", "FullBody", "Beginner", 3, "MaintainActive",
            isSystemDefault: true, targetGender: "Male & Female");

        var ranked = SplitRecommendationScorer.Rank([womenOnly, unisex], fit, "BuildMuscle");

        // The goal-matched women's program cannot outrank the unisex one.
        Assert.Equal(unisex.SplitId, ranked[0].SplitId);
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);
        Assert.Equal(unisex.SplitId, pick!.SplitId);
    }

    [Fact]
    public void Rank_ExcludesGymProgramForBodyweightUser_RegardlessOfGoalMatch()
    {
        // A barbell program matches the goal exactly, but a bodyweight user cannot
        // run it. The doable bodyweight split must rank first.
        var fit = PersonFit.From(170, 75, 28, 3, 45, "Beginner", "Bodyweight", "Active");
        var barbell = Split("Barbell Mass", "UpperLower", "Beginner", 3, "BuildMuscle",
            isSystemDefault: true, equipmentRequired: "Barbell, Cables, Machines");
        var bodyweight = Split("Bodyweight Builder", "Calisthenics", "Beginner", 3, "BuildMuscle",
            isSystemDefault: true, equipmentRequired: "Bodyweight");

        var ranked = SplitRecommendationScorer.Rank([barbell, bodyweight], fit, "BuildMuscle");

        Assert.Equal(bodyweight.SplitId, ranked[0].SplitId);
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);
        Assert.Equal(bodyweight.SplitId, pick!.SplitId);
    }

    [Fact]
    public void Rank_PrefersShorterSession_ForTimeCrunchedUser()
    {
        // Both fit the week and the goal; the 30-minute user should not be handed
        // the 75-minute block.
        var fit = PersonFit.From(170, 75, 30, 3, 30, "Intermediate", "FullGym", "Active");
        var longSession = Split("Long Block", "UpperLower", "Intermediate", 3, "BuildMuscle",
            isSystemDefault: true, minSessionMinutes: 60, maxSessionMinutes: 90);
        var shortSession = Split("Short Block", "FullBody", "Intermediate", 3, "BuildMuscle",
            isSystemDefault: true, minSessionMinutes: 25, maxSessionMinutes: 35);

        var ranked = SplitRecommendationScorer.Rank([longSession, shortSession], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(shortSession.SplitId, ranked[0].SplitId);
        Assert.Equal(shortSession.SplitId, pick!.SplitId);
    }

    [Fact]
    public void PickForAutoAssign_NeverPicksSpecialisationOrUtility_WhileAProgramExists()
    {
        // A 4-day week and a goal match make the dedicated arm plan and the deload
        // attractive to the scorer, but neither is a weekly program: the real
        // full-body block must win.
        var fit = PersonFit.From(175, 78, 30, 4, 60, "Intermediate", "FullGym", "Active");
        var real = Split("Upper / Lower Block", "UpperLower", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);
        var arms = Split("Awesome Arms", "BroSplit", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);
        arms.WorkoutTypeLabel = "Single Muscle Group";
        var deload = Split("2-Week Deload Workout Program", "BroSplit", "Intermediate", 4, "BuildMuscle", isSystemDefault: true);

        var ranked = SplitRecommendationScorer.Rank([arms, deload, real], fit, "BuildMuscle");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(real.SplitId, pick!.SplitId);
        Assert.True(SplitRecommendationScorer.IsAutoAssignable(arms) is false);
        Assert.True(SplitRecommendationScorer.IsAutoAssignable(deload) is false);
    }

    [Fact]
    public void Rank_DumbbellUser_PrefersDumbbellProgram_OverGymProgram()
    {
        var fit = PersonFit.From(175, 75, 30, 4, 45, "Intermediate", "Dumbbells", "Active");
        var gym = Split("Gym PPL", "PushPullLegs", "Intermediate", 4, "BuildMuscle",
            isSystemDefault: true, equipmentRequired: "Barbell, Cables, Machines");
        var dumbbell = Split("Dumbbell Upper / Lower", "UpperLower", "Intermediate", 4, "BuildMuscle",
            isSystemDefault: true, equipmentRequired: "Dumbbells, Bodyweight");

        var ranked = SplitRecommendationScorer.Rank([gym, dumbbell], fit, "BuildMuscle");

        Assert.Equal(dumbbell.SplitId, ranked[0].SplitId);
        Assert.True(SplitRecommendationScorer.IsEquipmentCompatible(dumbbell, fit));
        Assert.False(SplitRecommendationScorer.IsEquipmentCompatible(gym, fit));
    }

    [Fact]
    public void PickForAutoAssign_RejectsWomenProgramTaggedMaleAndFemale()
    {
        // Reported bug: the imported women's programs the scraper blanket-tagged
        // "Male & Female" slipped past the audience gate. The source categories
        // (Women, no Men) must still exclude them for a male user.
        var fit = PersonFit.From(185, 90, 24, 5, 45, "Advanced", "FullGym", "Sedentary", "Male");
        var women = Split("3 Day Full Body Toning Workout for Women", "FullBody", "Intermediate", 3, "LoseFat",
            isSystemDefault: true, targetGender: "Male & Female",
            sourceCategoriesJson: "[\"Women\",\"Fat Loss\",\"Full Body\"]");
        var unisex = Split("General Full Body", "FullBody", "Intermediate", 4, "LoseFat",
            isSystemDefault: true, targetGender: "Male & Female",
            sourceCategoriesJson: "[\"Women\",\"Fat Loss\",\"Men\",\"Full Body\"]");

        var ranked = SplitRecommendationScorer.Rank([women, unisex], fit, "LoseFat");
        var pick = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

        Assert.Equal(unisex.SplitId, pick!.SplitId);
    }

    [Fact]
    public void Rank_ReadsAudienceFromSourceCategories_WhenTagIsAmbiguous()
    {
        var male = PersonFit.From(180, 80, 28, 3, 45, "Intermediate", "FullGym", "Active", "Male");
        var female = PersonFit.From(165, 60, 28, 3, 45, "Intermediate", "FullGym", "Active", "Female");
        var women = Split("Women", "FullBody", "Intermediate", 3, "LoseFat", targetGender: "Male & Female",
            sourceCategoriesJson: "[\"Women\",\"Fat Loss\"]");
        var unisex = Split("Unisex", "FullBody", "Intermediate", 3, "LoseFat", targetGender: "Male & Female",
            sourceCategoriesJson: "[\"Women\",\"Men\",\"Fat Loss\"]");

        var maleRanked = SplitRecommendationScorer.Rank([women, unisex], male, "LoseFat");
        var femaleRanked = SplitRecommendationScorer.Rank([women, unisex], female, "LoseFat");

        Assert.Equal(unisex.SplitId, maleRanked[0].SplitId);
        Assert.Equal(women.SplitId, femaleRanked[0].SplitId);
        Assert.Contains("Designed for your profile", femaleRanked[0].MatchReason);
    }

    [Fact]
    public void Rank_PrefersMatchingAudience_ForFemaleUser()
    {
        var fit = PersonFit.From(165, 60, 28, 3, 45, "Beginner", "FullGym", "Active", "Female");
        var women = Split("Women's Program", "FullBody", "Beginner", 3, "BuildMuscle",
            isSystemDefault: true, targetGender: "Female");
        var men = Split("Men's Program", "FullBody", "Beginner", 3, "BuildMuscle",
            isSystemDefault: true, targetGender: "Male");

        var ranked = SplitRecommendationScorer.Rank([men, women], fit, "BuildMuscle");

        Assert.Equal(women.SplitId, ranked[0].SplitId);
        Assert.Contains("Designed for your profile", ranked[0].MatchReason);
    }

    [Fact]
    public void Rank_GluteFocusSplitsDifferByGender_EvenWithoutAudienceTags()
    {
        // Same library, same answers except gender: the soft category nudge must
        // make the male and female picks differ even though neither split is
        // explicitly gender-tagged.
        var female = PersonFit.From(165, 60, 28, 3, 45, "Intermediate", "FullGym", "Active", "Female");
        var male = PersonFit.From(180, 80, 28, 3, 45, "Intermediate", "FullGym", "Active", "Male");

        var glute = Split("Glute & Core", "GluteFocus", "Intermediate", 3, "BuildMuscle", isSystemDefault: true);
        var fullBody = Split("Full Body", "FullBody", "Intermediate", 3, "BuildMuscle", isSystemDefault: true);

        var femaleRanked = SplitRecommendationScorer.Rank([fullBody, glute], female, "BuildMuscle");
        var maleRanked = SplitRecommendationScorer.Rank([glute, fullBody], male, "BuildMuscle");

        Assert.Equal(glute.SplitId, femaleRanked[0].SplitId);
        Assert.Equal(fullBody.SplitId, maleRanked[0].SplitId);
    }

    [Fact]
    public void PersonFit_EighteenYearOld_IsTeenAndCappedAtBeginner()
    {
        // The requirement is 13-18 = beginner. Age 18 used to fall into the
        // unrestricted "Young" band and escape the safety ceiling.
        var fit = PersonFit.From(175m, 70m, 18,
            trainingDaysPerWeek: null, sessionDurationMinutes: null,
            trainingExperience: "Advanced", equipmentAccess: null, dailyActivityLevel: null);

        Assert.Equal("Teen", fit.AgeBand);
        Assert.Equal("Beginner", fit.PreferredLevel);
    }

    [Theory]
    [InlineData("Teen", "Advanced", "Beginner")]
    [InlineData("Masters", "Advanced", "Beginner")]
    [InlineData("Adult", "Advanced", "Advanced")]
    [InlineData("Adult", null, "Intermediate")]
    public void PersonFit_PreferredLevel_RespectsSafetyCeiling(string ageBandTarget, string? experience, string expectedLevel)
    {
        // Pick an age/weight/height combo that lands in the requested band and
        // (for the "Masters" case) a normal BMI, so only the age drives the cap.
        (byte age, decimal heightCm, decimal weightKg) = ageBandTarget switch
        {
            "Teen" => ((byte)16, 170m, 65m),
            "Masters" => ((byte)52, 170m, 70m),
            _ => ((byte)30, 170m, 70m)
        };

        var fit = PersonFit.From(heightCm, weightKg, age, trainingDaysPerWeek: null,
            sessionDurationMinutes: null, trainingExperience: experience, equipmentAccess: null, dailyActivityLevel: null);

        Assert.Equal(expectedLevel, fit.PreferredLevel);
    }
}
