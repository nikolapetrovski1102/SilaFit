using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class ExerciseSearchTermsTests
{
    private static List<string> Stems(string? text) =>
        ExerciseSearchTerms.Parse(text).Select(group => group[0]).ToList();

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("- / !")]
    [InlineData("the exercise")]
    public void NothingSearchable_GivesNoGroups(string? text)
    {
        Assert.Empty(ExerciseSearchTerms.Parse(text));
    }

    [Fact]
    public void ShoulderFly_IsTwoWords_ShoulderAlsoMatchingDelt()
    {
        var groups = ExerciseSearchTerms.Parse("Shoulder fly");

        Assert.Equal(2, groups.Count);
        Assert.Equal(["shoulder", "delt"], groups[0]);
        Assert.Equal("fly", groups[1][0]);
    }

    [Theory]
    [InlineData("flys", "fly")]
    [InlineData("flies", "fly")]
    [InlineData("flyes", "fly")]
    [InlineData("presses", "press")]
    [InlineData("press", "press")]
    [InlineData("lunges", "lunge")]
    [InlineData("rows", "row")]
    [InlineData("curls", "curl")]
    [InlineData("raises", "raise")]
    [InlineData("biceps", "bicep")]
    [InlineData("abs", "abdominal")]
    public void Plurals_FoldToAStemBothSpellingsContain(string word, string stem)
    {
        Assert.Equal([stem], Stems(word));
    }

    [Fact]
    public void Flye_AlsoMatchesFly()
    {
        Assert.Contains("fly", ExerciseSearchTerms.Parse("flye")[0]);
    }

    [Fact]
    public void GymShorthand_ExpandsToTheCatalogueSpelling()
    {
        var groups = ExerciseSearchTerms.Parse("DB bench");

        Assert.Contains("dumbbell", groups[0]);
        Assert.Equal("bench", groups[1][0]);
    }

    [Fact]
    public void HyphensAndCase_SplitIntoLowercaseWords()
    {
        Assert.Equal(["pull", "up"], Stems("Pull-Up"));
    }

    [Fact]
    public void FillerWordsAndRepeats_AreDropped()
    {
        Assert.Equal(["curl", "dumbbell"], Stems("curl with a dumbbell curls"));
    }

    [Fact]
    public void LongQueries_AreCappedAtSixWords()
    {
        Assert.Equal(6, ExerciseSearchTerms.Parse("one two three four five six seven eight").Count);
    }
}
