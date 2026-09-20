using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class IngredientSummaryFormatterTests
{
    [Fact]
    public void Summarize_AddsCountableQuantitiesInsteadOfCountingRows()
    {
        var result = IngredientSummaryFormatter.Summarize(["2 eggs", "2 Eggs", "2 eggs"]);

        Assert.Equal(["Eggs ×6"], result);
    }

    [Fact]
    public void Summarize_AddsCompatibleUnitsAndKeepsDifferentUnitsSeparate()
    {
        var result = IngredientSummaryFormatter.Summarize(
            ["1 cup oats", "1/2 cup Oats", "100 g oats", "½ cup berries", "1 ½ cups berries"]);

        Assert.Equal(["Oats ×1.5 cups + 100 g", "Berries ×2 cups"], result);
    }

    [Fact]
    public void Summarize_PreservesFirstSeenOrderAndCountsUnstructuredDuplicates()
    {
        var result = IngredientSummaryFormatter.Summarize(
            ["Salt to taste", "2 bananas", " salt to taste ", "1 banana"]);

        Assert.Equal(["Salt to taste ×2", "Bananas ×3"], result);
    }

    [Fact]
    public void Summarize_ParsesMixedAndUnicodeFractions()
    {
        var result = IngredientSummaryFormatter.Summarize(
            ["1 3/4 lb rolled oats", "1 ⅕lb rolled oats"]);

        Assert.Equal(["Rolled oats ×2.95 lbs"], result);
    }
}
