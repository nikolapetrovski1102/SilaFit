using System.Text.Json;
using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class TrainerDocumentImportMapperTests
{
    private static readonly AdminExerciseModel Bench = new() { ExerciseId = Guid.NewGuid(), Name = "Barbell Bench Press", MuscleGroup = "chest" };
    private static readonly AdminExerciseModel Squat = new() { ExerciseId = Guid.NewGuid(), Name = "Back Squat", MuscleGroup = "legs" };
    private static readonly List<AdminExerciseModel> Library = [Bench, Squat];

    private static JsonElement Days(ImportedProgram program) => JsonDocument.Parse(program.DaysJson).RootElement;

    [Fact]
    public void MapSplit_MatchesLibraryPick_AndKeepsUnknownExercisesForCreation()
    {
        var json = """
        { "name": "Push Pull", "description": null, "level": "advanced", "days": [
          { "dayIndex": 1, "title": "Push", "focusLabel": "Chest", "isRestDay": false, "estimatedMinutes": 70, "exercises": [
            { "name": "Bench press", "libraryName": "barbell bench press", "muscleGroup": "chest", "sets": 4, "repsLow": 6, "repsHigh": 8, "notes": null },
            { "name": "Cable Lateral Raise", "libraryName": null, "muscleGroup": "shoulders", "sets": 3, "repsLow": 12, "repsHigh": 15, "notes": "slow" } ] } ] }
        """;

        var program = TrainerDocumentImportMapper.MapSplit(json, Library, null);

        Assert.Equal("Push Pull", program.Name);
        Assert.Equal("Advanced", program.Level);
        Assert.Equal(7, program.DurationDays);
        var exercises = Days(program)[0].GetProperty("exercises");
        Assert.Equal(Bench.ExerciseId.ToString(), exercises[0].GetProperty("exerciseId").GetString());
        Assert.Equal("Barbell Bench Press", exercises[0].GetProperty("name").GetString());
        Assert.Equal(JsonValueKind.Null, exercises[1].GetProperty("exerciseId").ValueKind);
        Assert.Equal("Cable Lateral Raise", exercises[1].GetProperty("name").GetString());
    }

    [Fact]
    public void MapSplit_MultiWeek_RoundsDurationToWholeWeeks_AndSkipsBadOrDuplicateDays()
    {
        var json = """
        { "name": "Block", "description": "", "level": "Beginner", "days": [
          { "dayIndex": 1, "title": "Legs", "focusLabel": null, "isRestDay": false, "estimatedMinutes": null, "exercises": [
            { "name": "Back squat", "libraryName": null, "muscleGroup": "glutes", "sets": 40, "repsLow": 10, "repsHigh": 5, "notes": null } ] },
          { "dayIndex": 1, "title": "Duplicate", "focusLabel": null, "isRestDay": true, "estimatedMinutes": null, "exercises": [] },
          { "dayIndex": 400, "title": "Out of range", "focusLabel": null, "isRestDay": true, "estimatedMinutes": null, "exercises": [] },
          { "dayIndex": 9, "title": "Week 2 legs", "focusLabel": null, "isRestDay": false, "estimatedMinutes": 50, "exercises": [] } ] }
        """;

        var program = TrainerDocumentImportMapper.MapSplit(json, Library, "Fallback");

        Assert.Equal(2, program.DayCount);
        Assert.Equal(14, program.DurationDays);
        Assert.Null(program.Description);
        var days = Days(program);
        var squat = days[0].GetProperty("exercises")[0];
        Assert.Equal(Squat.ExerciseId.ToString(), squat.GetProperty("exerciseId").GetString());
        Assert.Equal(10, squat.GetProperty("sets").GetInt32());
        Assert.Equal(10, squat.GetProperty("repsLow").GetInt32());
        Assert.Equal(10, squat.GetProperty("repsHigh").GetInt32());
        // A training day with nothing in it becomes a rest day rather than an empty workout.
        Assert.True(days[1].GetProperty("isRestDay").GetBoolean());
    }

    [Fact]
    public void MapSplit_NoTrainingDays_Throws()
    {
        var json = """{ "name": "x", "description": null, "level": "Beginner", "days": [] }""";

        Assert.Throws<ValidationException>(() => TrainerDocumentImportMapper.MapSplit(json, Library, null));
    }

    [Fact]
    public void MapSplit_GarbageJson_ThrowsConflict()
    {
        Assert.Throws<ConflictException>(() => TrainerDocumentImportMapper.MapSplit("{not json", Library, null));
    }

    [Fact]
    public void MapDietPlan_CapsDurationAt26Weeks_AndCleansMeals()
    {
        var json = """
        { "name": "", "description": "Lean bulk", "days": [
          { "dayIndex": 182, "title": "Sunday", "meals": [
            { "mealType": "lunch", "title": "Chicken rice", "description": null, "calories": 650, "protein": 45, "carbs": 70, "fats": -3,
              "ingredients": ["150 g chicken", "  ", "100 g rice"], "steps": ["Cook rice.", "Grill chicken."] },
            { "mealType": "Brunch", "title": "Toast", "description": null, "calories": 200, "protein": 6, "carbs": 30, "fats": 5,
              "ingredients": [], "steps": [] } ] },
          { "dayIndex": 3, "title": "Empty", "meals": [] } ] }
        """;

        var program = TrainerDocumentImportMapper.MapDietPlan(json, "Coach Ana plan");

        Assert.Equal("Coach Ana plan", program.Name);
        Assert.Equal(182, program.DurationDays);
        Assert.Equal(1, program.DayCount);
        var meals = Days(program)[0].GetProperty("meals");
        Assert.Equal("Lunch", meals[0].GetProperty("mealType").GetString());
        Assert.Equal(0, meals[0].GetProperty("fats").GetInt32());
        Assert.Equal(2, meals[0].GetProperty("ingredients").GetArrayLength());
        Assert.Equal(2, meals[0].GetProperty("steps").GetArrayLength());
        Assert.Equal("Snack", meals[1].GetProperty("mealType").GetString());
    }

    [Theory]
    [InlineData("Barbell  Bench-Press", "barbell bench press")]
    [InlineData(" BACK squat ", "back squat")]
    public void NormalizeName_IgnoresCaseSpacingAndHyphens(string input, string expected) =>
        Assert.Equal(expected, TrainerDocumentImportMapper.NormalizeName(input));
}
