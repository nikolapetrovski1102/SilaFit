using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class PartnerServiceTests
{
    private readonly Mock<IPartnerLeadsProvider> partnerLeadsProvider = new(MockBehavior.Strict);
    private readonly Mock<IUserProfileProvider> userProfileProvider = new(MockBehavior.Strict);
    private readonly Mock<IMealPlanningService> mealPlanningService = new();
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);
    private readonly PartnerService sut;

    public PartnerServiceTests()
    {
        sut = new PartnerService(partnerLeadsProvider.Object, userProfileProvider.Object, mealPlanningService.Object, Options.Create(new PartnerOptions
        {
            Username = "partner",
            Password = "secret",
            PayloadKeyBase64 = Convert.ToBase64String(key),
            MaxPayloadAgeSeconds = 300
        }));
    }

    private PartnerEncryptedRequest Encrypted(object payload, string purpose) => new()
    {
        Payload = PartnerPayloadCipher.Encrypt(JsonSerializer.Serialize(payload), key, purpose)
    };

    private PartnerEncryptedRequest Provision(
        string partnerUserId = "lead-1", string email = "lead@example.com", string provider = "google", DateTime? issuedAtUtc = null,
        object? profile = null) =>
        Encrypted(new
        {
            partnerUserId,
            email,
            displayName = "  Lead Person  ",
            provider,
            issuedAtUtc = issuedAtUtc ?? DateTime.UtcNow,
            profile
        }, PartnerPayloadCipher.ProvisionPurpose);

    private static object FullProfile(string gender = "female", int ageYears = 29, decimal heightCm = 168.04m, string goal = "losefat") => new
    {
        gender,
        ageYears,
        heightCm,
        weightKg = 64,
        goal,
        trainingDaysPerWeek = 4,
        trainingExperience = "Beginner",
        equipmentAccess = "dumbbells",
        dailyActivityLevel = "LightlyActive"
    };

    private PartnerLeadResultDto Open(ServiceResult<PartnerEncryptedResponse> result, string purpose)
    {
        Assert.True(result.IsSuccess);
        var plaintext = PartnerPayloadCipher.TryDecrypt(result.Data!.Payload, key, purpose);
        Assert.NotNull(plaintext);
        return JsonSerializer.Deserialize<PartnerLeadResultDto>(plaintext, new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
    }

    private PartnerEncryptedRequest Cancel(string partnerUserId = "lead-1", DateTime? issuedAtUtc = null) =>
        Encrypted(new { partnerUserId, issuedAtUtc = issuedAtUtc ?? DateTime.UtcNow }, PartnerPayloadCipher.CancelPurpose);

    private void SetupProvision(PartnerLeadOutcomeModel outcome) =>
        partnerLeadsProvider.Setup(p => p.ProvisionAsync(
                "lead-1", "lead@example.com", "Lead Person", "Google", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(outcome);

    // ---- ProvisionLeadAsync ----

    [Fact]
    public async Task ProvisionLeadAsync_NewLead_ReturnsActiveWithNormalizedFields()
    {
        var userId = Guid.NewGuid();
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = userId, IsNewAccount = true, ProGranted = true });

        var issuedAt = DateTime.UtcNow;
        var result = await sut.ProvisionLeadAsync(Provision(issuedAtUtc: issuedAt));

        var response = Open(result, PartnerPayloadCipher.ProvisionResponsePurpose);
        Assert.Equal(userId, response.UserId);
        Assert.Equal("lead-1", response.PartnerUserId);
        Assert.Equal("Active", response.Status);
        Assert.True(response.IsNewAccount);
        Assert.True(response.ProGranted);
        Assert.True((issuedAt - response.RequestIssuedAtUtc).Duration() < TimeSpan.FromMilliseconds(1));
    }

    [Fact]
    public async Task ProvisionLeadAsync_Response_DoesNotDecryptAsRequestOrCancelResponse()
    {
        // The sealed response must not be usable as a request, or as the other endpoint's answer.
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = Guid.NewGuid(), ProGranted = true });

        var result = await sut.ProvisionLeadAsync(Provision());

        Assert.DoesNotContain("lead-1", result.Data!.Payload);
        Assert.Null(PartnerPayloadCipher.TryDecrypt(result.Data.Payload, key, PartnerPayloadCipher.ProvisionPurpose));
        Assert.Null(PartnerPayloadCipher.TryDecrypt(result.Data.Payload, key, PartnerPayloadCipher.CancelResponsePurpose));
    }

    [Fact]
    public async Task ProvisionLeadAsync_PassesIssuedAtTruncatedToMillisecondsInUtc()
    {
        var issuedAt = DateTime.UtcNow;
        DateTime captured = default;
        partnerLeadsProvider.Setup(p => p.ProvisionAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string?, string, DateTime, CancellationToken>((_, _, _, _, at, _) => captured = at)
            .ReturnsAsync(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = Guid.NewGuid() });

        await sut.ProvisionLeadAsync(Provision(issuedAtUtc: issuedAt));

        Assert.Equal(DateTimeKind.Utc, captured.Kind);
        Assert.Equal(0, captured.Ticks % TimeSpan.TicksPerMillisecond);
        Assert.True((issuedAt - captured).Duration() < TimeSpan.FromMilliseconds(1));
    }

    [Fact]
    public async Task ProvisionLeadAsync_PayloadEncryptedForCancel_Returns401()
    {
        var request = Encrypted(new
        {
            partnerUserId = "lead-1", email = "lead@example.com", provider = "Google", issuedAtUtc = DateTime.UtcNow
        }, PartnerPayloadCipher.CancelPurpose);

        var result = await sut.ProvisionLeadAsync(request);

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Theory]
    [InlineData(-10)]
    [InlineData(10)]
    public async Task ProvisionLeadAsync_IssuedAtOutsideWindow_Returns401(int minutes)
    {
        var result = await sut.ProvisionLeadAsync(Provision(issuedAtUtc: DateTime.UtcNow.AddMinutes(minutes)));

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Theory]
    [InlineData("", "lead@example.com", "Google")]
    [InlineData("lead-1", "not-an-email", "Google")]
    [InlineData("lead-1", "lead@example.com", "Facebook")]
    public async Task ProvisionLeadAsync_InvalidFields_Returns400(string partnerUserId, string email, string provider)
    {
        var result = await sut.ProvisionLeadAsync(Provision(partnerUserId, email, provider));

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ProvisionLeadAsync_DecryptsToNonJson_Returns400()
    {
        var request = new PartnerEncryptedRequest
        {
            Payload = PartnerPayloadCipher.Encrypt("not json", key, PartnerPayloadCipher.ProvisionPurpose)
        };

        var result = await sut.ProvisionLeadAsync(request);

        Assert.Equal(400, result.StatusCode);
    }

    [Theory]
    [InlineData("Stale")]
    [InlineData("EmailTaken")]
    [InlineData("AccountDisabled")]
    public async Task ProvisionLeadAsync_RejectedOutcome_Returns409(string outcome)
    {
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = outcome });

        var result = await sut.ProvisionLeadAsync(Provision());

        Assert.False(result.IsSuccess);
        Assert.Equal(409, result.StatusCode);
    }

    [Fact]
    public async Task ProvisionLeadAsync_WithProfile_SeedsCanonicalProfileAndRecomputesTargets()
    {
        var userId = Guid.NewGuid();
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = userId, IsNewAccount = true, ProGranted = true });
        UpsertUserProfileRequest? saved = null;
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserProfileModel?)null);
        userProfileProvider.Setup(p => p.UpsertAsync(userId, It.IsAny<UpsertUserProfileRequest>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, UpsertUserProfileRequest, CancellationToken>((_, request, _) => saved = request)
            .ReturnsAsync(new UserProfileModel { UserId = userId });

        var result = await sut.ProvisionLeadAsync(Provision(profile: FullProfile()));

        Assert.True(Open(result, PartnerPayloadCipher.ProvisionResponsePurpose).ProfileSaved);
        Assert.NotNull(saved);
        Assert.Equal("Female", saved.Gender);
        Assert.Equal(29, saved.AgeYears);
        Assert.Equal(168.0m, saved.HeightCm);
        Assert.Equal("LoseFat", saved.Goal);
        Assert.Equal(45, saved.SessionDurationMinutes);
        Assert.Equal("Dumbbells", saved.EquipmentAccess);
        mealPlanningService.Verify(m => m.RecomputeTargetsAsync(userId, It.IsAny<UserProfileModel>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ProvisionLeadAsync_AccountAlreadyHasProfile_KeepsIt()
    {
        var userId = Guid.NewGuid();
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = userId, ProGranted = true });
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserProfileModel { UserId = userId, Gender = "Male" });

        var result = await sut.ProvisionLeadAsync(Provision(profile: FullProfile()));

        // Strict mock: an UpsertAsync call would throw.
        Assert.False(Open(result, PartnerPayloadCipher.ProvisionResponsePurpose).ProfileSaved);
    }

    [Fact]
    public async Task ProvisionLeadAsync_WithoutProfile_DoesNotTouchProfile()
    {
        SetupProvision(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = Guid.NewGuid(), ProGranted = true });

        var result = await sut.ProvisionLeadAsync(Provision());

        Assert.False(Open(result, PartnerPayloadCipher.ProvisionResponsePurpose).ProfileSaved);
    }

    [Theory]
    [InlineData("Robot", 29, 168, "LoseFat")]
    [InlineData("Female", 12, 168, "LoseFat")]
    [InlineData("Female", 29, 99, "LoseFat")]
    [InlineData("Female", 29, 168, "GetStrong")]
    public async Task ProvisionLeadAsync_InvalidProfile_Returns400BeforeProvisioning(string gender, int ageYears, int heightCm, string goal)
    {
        // Strict mocks: provisioning or a profile write would throw.
        var result = await sut.ProvisionLeadAsync(Provision(profile: FullProfile(gender, ageYears, heightCm, goal)));

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ProvisionLeadAsync_ProfileMissingRequiredField_Returns400()
    {
        var result = await sut.ProvisionLeadAsync(Provision(profile: new { gender = "Male", ageYears = 30, heightCm = 180, weightKg = 80 }));

        Assert.Equal(400, result.StatusCode);
        Assert.Contains("profile.goal", result.UserMessage);
    }

    // ---- CancelLeadAsync ----

    [Fact]
    public async Task CancelLeadAsync_KnownLead_ReturnsCancelled()
    {
        var userId = Guid.NewGuid();
        partnerLeadsProvider.Setup(p => p.CancelAsync("lead-1", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PartnerLeadOutcomeModel { Outcome = "Ok", UserId = userId });

        var result = await sut.CancelLeadAsync(Cancel());

        var response = Open(result, PartnerPayloadCipher.CancelResponsePurpose);
        Assert.Equal(userId, response.UserId);
        Assert.Equal("Cancelled", response.Status);
    }

    [Fact]
    public async Task CancelLeadAsync_UnknownLead_Returns404()
    {
        partnerLeadsProvider.Setup(p => p.CancelAsync("lead-1", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PartnerLeadOutcomeModel { Outcome = "NotFound" });

        var result = await sut.CancelLeadAsync(Cancel());

        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task CancelLeadAsync_StaleRequest_Returns409()
    {
        partnerLeadsProvider.Setup(p => p.CancelAsync("lead-1", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PartnerLeadOutcomeModel { Outcome = "Stale" });

        var result = await sut.CancelLeadAsync(Cancel());

        Assert.Equal(409, result.StatusCode);
    }

    [Fact]
    public async Task CancelLeadAsync_ProvisionPayload_Returns401WithoutTouchingTheDatabase()
    {
        // Strict mock: any provider call would throw, so this also asserts none happen.
        var result = await sut.CancelLeadAsync(Provision());

        Assert.Equal(401, result.StatusCode);
    }
}
