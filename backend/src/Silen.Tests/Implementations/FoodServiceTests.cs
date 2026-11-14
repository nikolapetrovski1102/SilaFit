using System.Text.Json;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class FoodServiceTests
{
    private readonly Mock<IFoodNutritionProvider> provider = new(MockBehavior.Strict);
    private readonly Mock<IOpenFoodFactsClient> openFoodFacts = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionGate> subscriptionGate = new();
    private readonly Mock<IFoodScanProvider> foodScanProvider = new(MockBehavior.Strict);
    private readonly Mock<IPartnerFoodCatalogClient> partnerCatalog = new(MockBehavior.Strict);
    private readonly BarcodeOffTickets tickets = new(TimeProvider.System);
    private readonly FoodService sut;

    public FoodServiceTests()
    {
        // The partner catalog is off unless a test switches it on.
        partnerCatalog.Setup(c => c.GetProductAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((PartnerFoodProductModel?)null);
        // Nobody else has saved the barcode unless a test says so.
        provider.Setup(p => p.GetBarcodeSuggestionAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((BarcodeProductHintDto?)null);
        // Pro by default, so the barcode tests below exercise the lookup itself.
        subscriptionGate.Setup(g => g.HasActiveProAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>())).ReturnsAsync(true);
        sut = new FoodService(provider.Object, openFoodFacts.Object, subscriptionGate.Object, foodScanProvider.Object, partnerCatalog.Object, tickets);
    }

    [Fact]
    public async Task LookupBarcodeAsync_PartnerStocksIt_SavesUnderThePartnerWithoutAskingOpenFoodFacts()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        var product = new OpenFoodFactsProductModel
        {
            Barcode = "5310000000017", Name = "Ajvar blagi", SourceUrl = "https://paket.mk/p/ajvar",
            CaloriesKcal = 120, ProteinG = 2, CarbohydrateG = 10, FatG = 8
        };
        partnerCatalog.Setup(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PartnerFoodProductModel("Paket.mk", product));
        provider
            .Setup(p => p.SaveOpenFoodFactsAsync(product, "Ajvar blagi", "ajvar blagi", It.IsAny<byte[]>(), "Paket.mk", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 55 });

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.Equal(55, result.Data!.Food!.FoodNutritionId);
        openFoodFacts.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task LookupBarcodeAsync_PartnerMisses_FallsBackToOpenFoodFacts()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        openFoodFacts.Setup(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((OpenFoodFactsProductModel?)null);

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.False(result.Data!.Found);
        openFoodFacts.Verify(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()), Times.Once);
    }

    private void FreeTierWithTrial(Guid userId, bool allowed, long foodScanId = 11)
    {
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);
        foodScanProvider
            .Setup(p => p.TryReserveAsync(
                userId, "barcode", true, It.IsAny<DateTime>(), 0, IFoodScanService.BarcodeTrialLimit, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodScanReservationModel
            {
                Allowed = allowed, Used = allowed ? 1 : IFoodScanService.BarcodeTrialLimit, FoodScanId = allowed ? foodScanId : null
            });
    }

    [Fact]
    public async Task LookupBarcodeAsync_FreeWithTrialLeft_SpendsATrialScan()
    {
        var userId = Guid.NewGuid();
        FreeTierWithTrial(userId, allowed: true);
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 7 });

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.True(result.IsSuccess);
        foodScanProvider.Verify(p => p.TryReserveAsync(
            userId, "barcode", true, It.IsAny<DateTime>(), 0, IFoodScanService.BarcodeTrialLimit, It.IsAny<CancellationToken>()), Times.Once);
        foodScanProvider.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task LookupBarcodeAsync_FreeTrialSpent_ReturnsForbiddenWithoutLookingUp()
    {
        var userId = Guid.NewGuid();
        FreeTierWithTrial(userId, allowed: false);

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
        provider.VerifyNoOtherCalls();
        openFoodFacts.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task LookupBarcodeAsync_FreeLookupFails_ReleasesTheTrialScan()
    {
        var userId = Guid.NewGuid();
        FreeTierWithTrial(userId, allowed: true, foodScanId: 11);
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        openFoodFacts
            .Setup(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()))
            .ThrowsAsync(new HttpRequestException("down"));
        foodScanProvider.Setup(p => p.ReleaseAsync(userId, 11, It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.False(result.IsSuccess);
        foodScanProvider.Verify(p => p.ReleaseAsync(userId, 11, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task LookupBarcodeAsync_Pro_SkipsTheTrial()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 7 });

        await sut.LookupBarcodeAsync(userId, "5310000000017");

        foodScanProvider.VerifyNoOtherCalls();
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
    public async Task SearchAsync_MacedonianQuery_AlsoSearchesEnglish_OwnMatchesFirst()
    {
        var userId = Guid.NewGuid();
        var own = new FoodNutritionModel { FoodNutritionId = 1, Name = "Пилешка салата" };
        var catalog = new FoodNutritionModel { FoodNutritionId = 2, Name = "Chicken breast, raw" };
        provider
            .Setup(p => p.SearchAsync(userId, "пилешки гради", 25, It.IsAny<CancellationToken>()))
            .ReturnsAsync([own]);
        provider
            .Setup(p => p.SearchAsync(userId, "chicken breast", 25, It.IsAny<CancellationToken>()))
            .ReturnsAsync([catalog, own]);

        var result = await sut.SearchAsync(userId, "Пилешки гради", null);

        Assert.True(result.IsSuccess);
        Assert.Equal([1L, 2L], result.Data!.Select(f => f.FoodNutritionId));
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

    [Theory]
    [InlineData(null)]
    [InlineData("1234567")]
    [InlineData("123456789012345")]
    [InlineData("53100abc12345")]
    public async Task LookupBarcodeAsync_NotABarcode_FailsValidation(string? code)
    {
        var result = await sut.LookupBarcodeAsync(Guid.NewGuid(), code);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task LookupBarcodeAsync_LocalHit_SkipsOpenFoodFacts()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 7, Name = "Ajvar" });

        var result = await sut.LookupBarcodeAsync(userId, " 5310000000017 ");

        Assert.True(result.IsSuccess);
        Assert.True(result.Data!.Found);
        Assert.Equal(7, result.Data.Food!.FoodNutritionId);
        openFoodFacts.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task LookupBarcodeAsync_UpcA_AlsoTriesTheEan13Spelling()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "012345678905", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "0012345678905", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 3 });

        var result = await sut.LookupBarcodeAsync(userId, "012345678905");

        Assert.Equal(3, result.Data!.Food!.FoodNutritionId);
    }

    [Fact]
    public async Task LookupBarcodeAsync_LocalMiss_SavesAPlausibleOpenFoodFactsProduct()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        var product = new OpenFoodFactsProductModel
        {
            Barcode = "5310000000017", Name = "Ajvar blagi", BrandName = "Zito",
            CaloriesKcal = 120, ProteinG = 2, CarbohydrateG = 10, FatG = 8
        };
        openFoodFacts
            .Setup(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(product);
        provider
            .Setup(p => p.SaveOpenFoodFactsAsync(product, "Ajvar blagi", "ajvar blagi", It.Is<byte[]>(h => h.Length == 32), "Open Food Facts", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodNutritionModel { FoodNutritionId = 99, Name = "Ajvar blagi" });

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.True(result.Data!.Found);
        Assert.Equal(99, result.Data.Food!.FoodNutritionId);
    }

    [Theory]
    [InlineData(null, 2, 10, 8)]   // missing energy
    [InlineData(2000.0, 2, 10, 8)] // kJ typed as kcal
    [InlineData(120.0, 60, 50, 8)] // macros over 100 g
    public async Task LookupBarcodeAsync_IncompleteOrImplausibleProduct_ReturnsAHintOnly(
        double? kcal, double protein, double carbs, double fat)
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        openFoodFacts
            .Setup(c => c.GetProductAsync("5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new OpenFoodFactsProductModel
            {
                Barcode = "5310000000017", Name = "Ajvar blagi", BrandName = "Zito", ImageUrl = "https://img/x.jpg",
                CaloriesKcal = (decimal?)kcal, ProteinG = (decimal)protein, CarbohydrateG = (decimal)carbs, FatG = (decimal)fat
            });

        var result = await sut.LookupBarcodeAsync(userId, "5310000000017");

        Assert.False(result.Data!.Found);
        Assert.Equal("Ajvar blagi", result.Data.Hint!.Name);
        Assert.Equal("https://img/x.jpg", result.Data.Hint.ImageUrl);
    }

    [Fact]
    public async Task LookupBarcodeAsync_UnknownEverywhere_ReturnsNotFound()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "53100000000", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        openFoodFacts
            .Setup(c => c.GetProductAsync("53100000000", It.IsAny<CancellationToken>()))
            .ReturnsAsync((OpenFoodFactsProductModel?)null);

        var result = await sut.LookupBarcodeAsync(userId, "53100000000");

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.Found);
        Assert.Null(result.Data.Hint);
        Assert.Equal("53100000000", result.Data.Barcode);
    }

    [Fact]
    public async Task LookupBarcodeAsync_OffOnDevice_MissAsksThePhoneWithoutCallingOpenFoodFacts()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "53100000000", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);

        // openFoodFacts is strict with no setup: any server-side OFF call fails the test.
        var result = await sut.LookupBarcodeAsync(userId, "53100000000", openFoodFactsOnDevice: true);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.Found);
        Assert.True(result.Data.CheckOpenFoodFacts);
        Assert.True(tickets.TryConsume(userId, "53100000000"));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task LookupBarcodeAsync_UnknownToOffButSavedByAnotherUser_PrefillsTheirNameOnly(bool offOnDevice)
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5319991488274", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        openFoodFacts
            .Setup(c => c.GetProductAsync("5319991488274", It.IsAny<CancellationToken>()))
            .ReturnsAsync((OpenFoodFactsProductModel?)null);
        var suggestion = new BarcodeProductHintDto { Name = "Ajvar blagi", BrandName = "Vitaminka", ServingSizeG = 30 };
        provider
            .Setup(p => p.GetBarcodeSuggestionAsync(userId, "5319991488274", It.IsAny<CancellationToken>()))
            .ReturnsAsync(suggestion);

        var result = await sut.LookupBarcodeAsync(userId, "5319991488274", offOnDevice);

        Assert.False(result.Data!.Found);
        Assert.Same(suggestion, result.Data.Hint);
    }

    [Fact]
    public async Task SaveDeviceOpenFoodFactsProductAsync_WithTicket_SavesAPlausibleProductOnce()
    {
        var userId = Guid.NewGuid();
        tickets.Issue(userId, "5310000000017");
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        var saved = new FoodNutritionModel { Name = "Ajvar blagi" };
        provider
            .Setup(p => p.SaveOpenFoodFactsAsync(
                It.Is<OpenFoodFactsProductModel>(m => m.Barcode == "5310000000017" && m.CaloriesKcal == 90m),
                "Ajvar blagi", "ajvar blagi", It.Is<byte[]>(h => h.Length == 32), "Open Food Facts", It.IsAny<CancellationToken>()))
            .ReturnsAsync(saved);

        var body = JsonDocument.Parse("""
            {"status":1,"product":{"product_name":"Ajvar blagi","brands":"Vitaminka",
             "nutriments":{"energy-kcal_100g":90,"proteins_100g":1.5,"carbohydrates_100g":9,"fat_100g":5}}}
            """).RootElement;

        var first = await sut.SaveDeviceOpenFoodFactsProductAsync(userId, "5310000000017", body);
        var replay = await sut.SaveDeviceOpenFoodFactsProductAsync(userId, "5310000000017", body);

        Assert.Same(saved, first.Data!.Food);
        Assert.Equal(400, replay.StatusCode);
    }

    [Fact]
    public async Task SaveDeviceOpenFoodFactsProductAsync_WithoutTicket_IsRefusedWithoutSaving()
    {
        var body = JsonDocument.Parse("""{"status":1,"product":{"product_name":"X"}}""").RootElement;

        var result = await sut.SaveDeviceOpenFoodFactsProductAsync(Guid.NewGuid(), "5310000000017", body);

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveDeviceOpenFoodFactsProductAsync_ImplausibleNutrition_ReturnsAHintOnly()
    {
        var userId = Guid.NewGuid();
        tickets.Issue(userId, "5310000000017");
        provider
            .Setup(p => p.GetByBarcodeAsync(userId, "5310000000017", It.IsAny<CancellationToken>()))
            .ReturnsAsync((FoodNutritionModel?)null);
        // kJ typed as kcal: far above what the macros allow.
        var body = JsonDocument.Parse("""
            {"status":1,"product":{"product_name":"Ajvar blagi",
             "nutriments":{"energy-kcal_100g":2500,"proteins_100g":1.5,"carbohydrates_100g":9,"fat_100g":5}}}
            """).RootElement;

        var result = await sut.SaveDeviceOpenFoodFactsProductAsync(userId, "5310000000017", body);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.Found);
        Assert.Equal("Ajvar blagi", result.Data.Hint!.Name);
    }

    [Fact]
    public async Task CreateCustomAsync_BadBarcode_FailsValidation()
    {
        var food = Food();
        food.Barcode = "12ab";

        var result = await sut.CreateCustomAsync(Guid.NewGuid(), food);

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public void OpenFoodFactsParse_ReadsStringNumbers_AndConvertsSodium()
    {
        using var doc = System.Text.Json.JsonDocument.Parse("""
            {"status":1,"product":{"product_name":"","product_name_mk":"Ајвар","brands":"Žito, Group",
             "image_front_small_url":"https://img/a.jpg","serving_quantity":"30",
             "nutriments":{"energy-kcal_100g":120,"proteins_100g":"2.5","carbohydrates_100g":10,"fat_100g":8,"sodium_100g":0.4}}}
            """);

        var product = OpenFoodFactsClient.Parse("5310000000017", doc.RootElement)!;

        Assert.Equal("Ајвар", product.Name);
        Assert.Equal("Žito", product.BrandName);
        Assert.Equal(30m, product.ServingSizeG);
        Assert.Equal(2.5m, product.ProteinG);
        Assert.Equal(400m, product.SodiumMg);
        Assert.True(product.HasHeadlineNutrients);
    }

    [Fact]
    public void OpenFoodFactsParse_UnknownProduct_IsNull()
    {
        using var doc = System.Text.Json.JsonDocument.Parse("""{"status":0,"status_verbose":"product not found"}""");

        Assert.Null(OpenFoodFactsClient.Parse("5310000000017", doc.RootElement));
    }
}
