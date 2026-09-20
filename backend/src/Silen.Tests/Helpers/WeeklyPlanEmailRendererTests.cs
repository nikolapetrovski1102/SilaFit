using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class WeeklyPlanEmailRendererTests
{
    [Fact]
    public void BuildHtml_UsesCompactEncodedIngredientPreview()
    {
        var html = WeeklyPlanEmailRenderer.BuildHtml(
            "Taylor",
            "Strength Week",
            splitKept: false,
            "Balanced Meals",
            ["Chicken & rice", "Broccoli", "Eggs", "Oats", "Salmon", "Spinach"],
            new DateTime(2026, 9, 21));

        Assert.Contains("Ingredients preview", html);
        Assert.Contains("Chicken &amp; rice &middot; Broccoli &middot; Eggs &middot; Oats", html);
        Assert.Contains("+2 more", html);
        Assert.DoesNotContain("Salmon", html);
        Assert.DoesNotContain("<ul", html);
    }
}
