using Silen.Common.Helpers;
using Silen.Common.Models;
using Xunit;

namespace Silen.Tests.Helpers;

public class ExerciseCloseMatchesTests
{
    private static readonly List<ExerciseModel> Catalogue =
    [
        Exercise("Barbell Bench Press"),
        Exercise("Incline Dumbbell Bench Press"),
        Exercise("Tricep Rope Pushdown"),
        Exercise("Bulgarian Split Squat"),
        Exercise("Pull-Up"),
        Exercise("Seated Cable Row"),
        Exercise("Barbell Hip Thrust")
    ];

    private static ExerciseModel Exercise(string name) => new() { ExerciseId = Guid.NewGuid(), Name = name };

    private static List<string> Names(string search) =>
        ExerciseCloseMatches.Find(Catalogue, search, 6).Select(e => e.Name).ToList();

    [Fact]
    public void SwappedLetters_StillFindTheExercise()
    {
        Assert.Equal("Barbell Bench Press", Names("benhc press")[0]);
    }

    [Theory]
    [InlineData("tricpe pushdown", "Tricep Rope Pushdown")]
    [InlineData("bulgarain split squat", "Bulgarian Split Squat")]
    [InlineData("pulup", "Pull-Up")]
    [InlineData("hip thurst", "Barbell Hip Thrust")]
    public void Typos_FindTheIntendedExerciseFirst(string search, string expected)
    {
        Assert.Equal(expected, Names(search)[0]);
    }

    [Theory]
    [InlineData("zercher carry")]
    [InlineData("nordic curl")]
    [InlineData("")]
    [InlineData("the")]
    public void NothingClose_GivesNoMatches(string search)
    {
        Assert.Empty(Names(search));
    }

    [Fact]
    public void ShortWords_MustMatchExactly()
    {
        // "rw" is one edit from "row", but two letters is too little to guess from.
        Assert.Empty(Names("rw"));
    }

}
