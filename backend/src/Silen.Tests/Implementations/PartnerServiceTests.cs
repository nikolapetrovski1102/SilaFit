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
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class PartnerServiceTests
{
    private readonly Mock<IPartnerLeadsProvider> partnerLeadsProvider = new(MockBehavior.Strict);
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);
    private readonly PartnerService sut;

    public PartnerServiceTests()
    {
        sut = new PartnerService(partnerLeadsProvider.Object, Options.Create(new PartnerOptions
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
        string partnerUserId = "lead-1", string email = "lead@example.com", string provider = "google", DateTime? issuedAtUtc = null) =>
        Encrypted(new
        {
            partnerUserId,
            email,
            displayName = "  Lead Person  ",
            provider,
            issuedAtUtc = issuedAtUtc ?? DateTime.UtcNow
        }, PartnerPayloadCipher.ProvisionPurpose);

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
