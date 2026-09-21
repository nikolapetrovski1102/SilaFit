using Silen.Services.Helpers;

namespace Silen.Tests.Helpers;

public sealed class DietPlanHeroImagesTests
{
    [Theory]
    [InlineData("BuildMuscle", DietPlanHeroImages.BuildMuscle)]
    [InlineData("LoseFat", DietPlanHeroImages.LoseFat)]
    [InlineData("MaintainActive", DietPlanHeroImages.MaintainActive)]
    [InlineData(null, DietPlanHeroImages.General)]
    [InlineData("Unknown", DietPlanHeroImages.General)]
    public void ForGoal_returns_expected_production_image(string? goal, string expected)
    {
        Assert.Equal(expected, DietPlanHeroImages.ForGoal(goal));
    }
}
