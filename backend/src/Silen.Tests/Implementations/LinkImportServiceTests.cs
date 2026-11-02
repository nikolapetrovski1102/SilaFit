using System.Text.Json;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class LinkImportServiceTests
{
    private const string Link = "Check this out! https://www.tiktok.com/@coach/video/7300000000000000001?lang=en";
    private const string VideoId = "7300000000000000001";

    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly Mock<IUserSettingsProvider> userSettingsProvider = new(MockBehavior.Strict);
    private readonly Mock<ILinkScanProvider> linkScanProvider = new(MockBehavior.Strict);
    private readonly Mock<ILinkPreviewClient> linkPreviewClient = new(MockBehavior.Strict);
    private readonly Mock<IExercisesProvider> exercisesProvider = new(MockBehavior.Strict);
    private readonly Mock<IOpenRouterClient> openRouterClient = new(MockBehavior.Strict);
    private readonly LinkImportService sut;
    private readonly Guid userId = Guid.NewGuid();
    private readonly Guid squatId = Guid.NewGuid();

    public LinkImportServiceTests()
    {
        sut = new LinkImportService(
            subscriptionGate.Object, userSettingsProvider.Object, linkScanProvider.Object, linkPreviewClient.Object,
            exercisesProvider.Object, openRouterClient.Object,
            Options.Create(new OpenRouterOptions { LinkImportModel = "test/text" }), TimeProvider.System);

        userSettingsProvider
            .Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSettingsModel { UserId = userId, AiDataConsentAtUtc = DateTime.UtcNow });
        linkPreviewClient
            .Setup(c => c.GetTikTokPreviewAsync(It.IsAny<Uri>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new LinkPreviewModel
            {
                Provider = TikTokLinks.Provider, VideoId = VideoId, Url = "https://www.tiktok.com/@coach/video/" + VideoId,
                Caption = "Leg day: squats 4x6-8", AuthorName = "coach"
            });
        linkScanProvider.Setup(p => p.GetCachedAsync(TikTokLinks.Provider, VideoId, It.IsAny<CancellationToken>())).ReturnsAsync((string?)null);
        linkScanProvider.Setup(p => p.PutCachedAsync(TikTokLinks.Provider, VideoId, It.IsAny<string>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
        exercisesProvider
            .Setup(p => p.GetPickableAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new ExerciseModel { ExerciseId = squatId, Name = "Barbell Back Squat", MuscleGroup = "legs" }]);
        Usage(0, 0, 0);
    }

    private void Tier(string tier)
    {
        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(tier == "advanced");
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(tier is "pro" or "advanced");
    }

    private void Usage(int workout, int meal, int trial) =>
        linkScanProvider
            .Setup(p => p.GetUsageAsync(userId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new LinkScanUsageModel { WorkoutToday = workout, MealToday = meal, TrialUsed = trial });

    private void AiReturns(object response) =>
        openRouterClient
            .Setup(c => c.GenerateJsonAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<JsonElement>(), "test/text", It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(JsonSerializer.Serialize(response));

    private static object WorkoutAnswer() => new
    {
        kind = "workout", title = "Leg day", notes = "",
        exercises = new[] { new { name = "Barbell Back Squat", libraryName = "Barbell Back Squat", muscleGroup = "legs", sets = 4, repsLow = 6, repsHigh = 8 } },
        items = Array.Empty<object>()
    };

    private static object MealAnswer() => new
    {
        kind = "meal", title = "Chicken rice bowl", notes = "",
        exercises = Array.Empty<object>(),
        items = new[]
        {
            new { name = "chicken breast, grilled", grams = 150m, kcalPer100g = 165m, proteinPer100g = 31m, carbsPer100g = 0m, fatPer100g = 3.6m, fiberPer100g = 0m, assumed = false, confidence = "high" }
        }
    };

    private void AllowReservation(string kind, bool trial, long id = 7) =>
        linkScanProvider
            .Setup(p => p.TryReserveAsync(userId, kind, trial, It.IsAny<DateTime>(), ILinkImportService.DailyLimit, ILinkImportService.TrialLimit, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new LinkScanReservationModel { Allowed = true, Used = 1, LinkScanId = id });

    [Fact]
    public async Task ImportAsync_ProWorkout_MatchesLibraryAndReservesWorkoutScan()
    {
        Tier("pro");
        AiReturns(WorkoutAnswer());
        AllowReservation("workout", trial: false);

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.True(result.IsSuccess);
        Assert.Equal("workout", result.Data!.Kind);
        var exercise = Assert.Single(result.Data.Exercises);
        Assert.Equal(squatId, exercise.ExerciseId);
        Assert.Equal((4, 6, 8), (exercise.Sets, exercise.RepsLow, exercise.RepsHigh));
        Assert.False(result.Data.Quota.Meal.IsAvailable);
        linkScanProvider.Verify(p => p.PutCachedAsync(TikTokLinks.Provider, VideoId, It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ImportAsync_ProMeal_ReturnsForbiddenWithoutUsingAScan()
    {
        Tier("pro");
        AiReturns(MealAnswer());

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.Equal(403, result.StatusCode);
        linkScanProvider.Verify(p => p.TryReserveAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ImportAsync_AdvancedMeal_ReturnsIngredients()
    {
        Tier("advanced");
        AiReturns(MealAnswer());
        AllowReservation("meal", trial: false);

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.True(result.IsSuccess);
        Assert.Equal("meal", result.Data!.Kind);
        var item = Assert.Single(result.Data.Meal!.Items);
        Assert.Equal(150m, item.EstimatedGrams);
    }

    [Fact]
    public async Task ImportAsync_FreeMeal_UsesTrialScan()
    {
        Tier("free");
        Usage(0, 0, 4);
        AiReturns(MealAnswer());
        AllowReservation("meal", trial: true);

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.True(result.IsSuccess);
        Assert.Equal("free", result.Data!.Quota.Tier);
    }

    [Fact]
    public async Task ImportAsync_FreeTrialSpent_RefusesBeforeAnyNetworkOrAi()
    {
        Tier("free");
        Usage(0, 0, ILinkImportService.TrialLimit);

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.Equal(403, result.StatusCode);
        linkPreviewClient.Verify(c => c.GetTikTokPreviewAsync(It.IsAny<Uri>(), It.IsAny<CancellationToken>()), Times.Never);
        openRouterClient.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ImportAsync_AdvancedWorkoutDailySpent_Returns429()
    {
        Tier("advanced");
        Usage(ILinkImportService.DailyLimit, 0, 0);
        AiReturns(WorkoutAnswer());
        linkScanProvider
            .Setup(p => p.TryReserveAsync(userId, "workout", false, It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new LinkScanReservationModel { Allowed = false, Used = ILinkImportService.DailyLimit });

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.Equal(429, result.StatusCode);
    }

    [Fact]
    public async Task ImportAsync_OtherPost_DoesNotUseAScan()
    {
        Tier("advanced");
        AiReturns(new { kind = "other", title = "", notes = "", exercises = Array.Empty<object>(), items = Array.Empty<object>() });

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.True(result.IsSuccess);
        Assert.Equal("other", result.Data!.Kind);
        linkScanProvider.Verify(p => p.TryReserveAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ImportAsync_CachedPost_SkipsTheAi()
    {
        Tier("pro");
        linkScanProvider
            .Setup(p => p.GetCachedAsync(TikTokLinks.Provider, VideoId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(JsonSerializer.Serialize(WorkoutAnswer()));
        AllowReservation("workout", trial: false);

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.True(result.IsSuccess);
        openRouterClient.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ImportAsync_NotATikTokLink_Returns400()
    {
        Tier("advanced");

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = "https://example.com/video/123456789" });

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ImportAsync_WithoutAiConsent_ReturnsConsentRequired()
    {
        Tier("advanced");
        userSettingsProvider
            .Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSettingsModel { UserId = userId, AiDataConsentAtUtc = null });

        var result = await sut.ImportAsync(userId, new LinkImportRequest { Url = Link });

        Assert.Equal(428, result.StatusCode);
    }

    [Theory]
    [InlineData("https://vm.tiktok.com/ZMabc123/", true, null)]
    [InlineData("look https://www.tiktok.com/@a.b/video/7301234567890123456?is_from_webapp=1 !", true, "7301234567890123456")]
    [InlineData("http://m.tiktok.com/v/7301234567890123456.html", true, "7301234567890123456")]
    [InlineData("https://tiktok.com.evil.example/@a/video/7301234567890123456", false, null)]
    [InlineData("https://eviltiktok.com/@a/video/7301234567890123456", false, null)]
    [InlineData("no link here", false, null)]
    public void TikTokLinks_ParsesOnlyTikTokHosts(string text, bool ok, string? videoId)
    {
        Assert.Equal(ok, TikTokLinks.TryParse(text, out var uri));
        if (ok)
        {
            Assert.Equal("https", uri.Scheme);
            Assert.Equal(videoId, TikTokLinks.VideoId(uri));
        }
    }

    [Fact]
    public void MapExercises_ClampsSetsAndRepsAndDropsDuplicates()
    {
        var ai = new LinkImportMapper.AiLinkResult
        {
            Kind = "workout",
            Exercises =
            [
                new() { Name = "Back squat", LibraryName = "Barbell Back Squat", MuscleGroup = "legs", Sets = 40, RepsLow = 12, RepsHigh = 6 },
                new() { Name = "Barbell Back Squat", MuscleGroup = "legs", Sets = 3, RepsLow = 5, RepsHigh = 5 },
                new() { Name = "Zercher Carry", MuscleGroup = "nonsense", Sets = 0, RepsLow = 0, RepsHigh = 0 }
            ]
        };

        var result = LinkImportMapper.MapExercises(ai, [new ExerciseModel { ExerciseId = squatId, Name = "Barbell Back Squat", MuscleGroup = "legs" }]);

        Assert.Equal(2, result.Count);
        Assert.Equal((10, 12, 12), (result[0].Sets, result[0].RepsLow, result[0].RepsHigh));
        Assert.Null(result[1].ExerciseId);
        Assert.Equal("core", result[1].MuscleGroup);
        Assert.Equal((3, 8, 8), (result[1].Sets, result[1].RepsLow, result[1].RepsHigh));
    }
}
