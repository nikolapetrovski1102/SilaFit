using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class FoodServiceTests
{
    private readonly Mock<IFoodNutritionProvider> provider = new(MockBehavior.Strict);
    private readonly FoodService sut;

    public FoodServiceTests()
    {
        sut = new FoodService(provider.Object);
    }

    private static CreateCustomFoodRequest Food(
        string name = "Grandma's Ajvar", decimal kcal = 120, decimal protein = 2, decimal carbs = 10, decimal fat = 8) => new()
    {
        Name = name,
        CaloriesKcal = kcal,
        ProteinG = protein,
        CarbohydrateG = carbs,
        FatG = fat
    };

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" a ")]
    [InlineData("--")]
    public async Task SearchAsync_TooShortQuery_ReturnsEmpty_WithoutQuerying(string? query)
    {
        var result = await sut.SearchAsync(Guid.NewGuid(), query, null);

        Assert.True(result.IsSuccess);
        Assert.Empty(result.Data!);
    }

    [Fact]
    public async Task SearchAsync_NormalizesLikeTheImporter_AndClampsTake()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.SearchAsync(userId, "chicken breast raw", 50, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new FoodNutritionModel { Name = "Chicken breast, raw" }]);

        var result = await sut.SearchAsync(userId, "  Chicken   BREAST, (raw) ", 500);

        Assert.True(result.IsSuccess);
        Assert.Single(result.Data!);
    }

    [Fact]
    public async Task CreateCustomAsync_ValidFood_StoresNormalizedName_AndAUniqueHash()
    {
        var userId = Guid.NewGuid();
        var hashes = new List<byte[]>();
        provider
            .Setup(p => p.CreateCustomAsync(userId, It.IsAny<CreateCustomFoodRequest>(), "grandma s ajvar",
                It.Is<string>(id => id.StartsWith("user:")), It.IsAny<byte[]>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, CreateCustomFoodRequest, string, string, byte[], CancellationToken>((_, _, _, _, hash, _) => hashes.Add(hash))
            .ReturnsAsync(new FoodNutritionModel { IsCustom = true });

        Assert.True((await sut.CreateCustomAsync(userId, Food())).IsSuccess);
        Assert.True((await sut.CreateCustomAsync(userId, Food())).IsSuccess);

        Assert.Equal(2, hashes.Count);
        Assert.All(hashes, h => Assert.Equal(32, h.Length));
        Assert.NotEqual(hashes[0], hashes[1]);
    }

    [Theory]
    [InlineData("  ", 100, 1, 1, 1)]
    [InlineData("Oil", 950, 0, 0, 100)]
    [InlineData("Oil", 900, 0, 0, 101)]
    [InlineData("Mix", 400, 60, 60, 0)]
    [InlineData("Bad", -1, 1, 1, 1)]
    [InlineData("Water", 0, 0, 0, 0)]
    public async Task CreateCustomAsync_InvalidFood_FailsValidation(string name, decimal kcal, decimal protein, decimal carbs, decimal fat)
    {
        var result = await sut.CreateCustomAsync(Guid.NewGuid(), Food(name, kcal, protein, carbs, fat));

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }
}
