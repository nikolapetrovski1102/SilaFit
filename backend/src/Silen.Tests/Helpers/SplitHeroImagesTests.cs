using Silen.Services.Helpers;

namespace Silen.Tests.Helpers;

public sealed class SplitHeroImagesTests
{
    [Theory]
    [InlineData("PushPullLegs", SplitHeroImages.PushPullLegs)]
    [InlineData("ArnoldSplit", SplitHeroImages.PushPullLegs)]
    [InlineData("UpperLower", SplitHeroImages.UpperLower)]
    [InlineData("PHUL", SplitHeroImages.UpperLower)]
    [InlineData("BroSplit", SplitHeroImages.BroSplit)]
    [InlineData("Powerlifting", SplitHeroImages.Strength)]
    [InlineData("PHAT", SplitHeroImages.Hypertrophy)]
    [InlineData("Circuit", SplitHeroImages.Conditioning)]
    [InlineData("FullBody", SplitHeroImages.General)]
    public void Curated_category_picks_its_artwork(string category, string expected)
    {
        Assert.Equal(expected, SplitHeroImages.ForSplit(category, "Awesome Split 1", null));
    }

    [Theory]
    [InlineData("My Push Pull Legs", SplitHeroImages.PushPullLegs)]
    [InlineData("PPL 6x", SplitHeroImages.PushPullLegs)]
    [InlineData("Upper/Lower 4 day", SplitHeroImages.UpperLower)]
    [InlineData("Summer strength block", SplitHeroImages.Strength)]
    [InlineData("HIIT burner", SplitHeroImages.Conditioning)]
    [InlineData("Winter bulk", SplitHeroImages.Hypertrophy)]
    [InlineData("Chest & arms", SplitHeroImages.BroSplit)]
    [InlineData("Full body basics", SplitHeroImages.General)]
    [InlineData("Awesome Split 3", SplitHeroImages.Custom)]
    public void Custom_split_falls_back_to_name_keywords(string name, string expected)
    {
        Assert.Equal(expected, SplitHeroImages.ForSplit("Custom", name, null));
    }

    [Fact]
    public void Resolve_keeps_an_explicit_url()
    {
        const string url = "https://images.sila.fitness/splits/coach.png";
        Assert.Equal(url, SplitHeroImages.Resolve(url, "Custom", "PPL", null));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    [InlineData(SplitHeroImages.Custom)]
    public void Resolve_rederives_when_nothing_explicit_was_sent(string? requested)
    {
        Assert.Equal(SplitHeroImages.UpperLower, SplitHeroImages.Resolve(requested, "Custom", "Upper Lower", null));
    }
}
