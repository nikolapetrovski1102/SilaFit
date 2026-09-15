using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Enums;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AuthServiceTests
{
    private readonly Mock<IAuthProvider> authProvider = new(MockBehavior.Strict);
    private readonly Mock<IGoogleTokenVerifier> googleTokenVerifier = new(MockBehavior.Strict);
    private readonly Mock<IAppleTokenVerifier> appleTokenVerifier = new(MockBehavior.Strict);
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly AuthService sut;

    public AuthServiceTests()
    {
        var jwtOptions = Options.Create(new JwtOptions
        {
            Issuer = "silen-tests",
            Audience = "silen-app",
            SigningKey = "unit-test-signing-key-at-least-256-bits-long!!",
            ExpiryMinutes = 60
        });

        var reviewerBypassOptions = Options.Create(new ReviewerBypassOptions());

        sut = new AuthService(authProvider.Object, googleTokenVerifier.Object, appleTokenVerifier.Object, emailSender.Object, jwtOptions, reviewerBypassOptions);
    }

    private static UserAccountModel User(Guid? userId = null, string? email = "user@example.com", byte[]? passwordHash = null, byte[]? passwordSalt = null) => new()
    {
        UserId = userId ?? Guid.NewGuid(),
        Email = email,
        DisplayName = "Test User",
        AccountTier = AccountTier.Registered,
        PasswordHash = passwordHash,
        PasswordSalt = passwordSalt,
        CreatedAtUtc = DateTime.UtcNow,
        IsActive = true
    };

    // ---- LoginWithDeviceAsync ----

    [Fact]
    public async Task LoginWithDeviceAsync_EmptyDeviceId_Fails()
    {
        var result = await sut.LoginWithDeviceAsync("   ");

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginWithDeviceAsync_ProviderReturnsNull_Fails()
    {
        authProvider.Setup(p => p.GetOrCreateDeviceUserAsync("device-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);

        var result = await sut.LoginWithDeviceAsync("device-1");

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginWithDeviceAsync_Success_ReturnsTokenAndUserFields()
    {
        var user = User(email: null);
        authProvider.Setup(p => p.GetOrCreateDeviceUserAsync("device-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);

        var result = await sut.LoginWithDeviceAsync("device-1");

        Assert.True(result.IsSuccess);
        Assert.False(string.IsNullOrWhiteSpace(result.Data!.Token));
        Assert.Equal(user.UserId, result.Data.UserId);
        Assert.Equal(nameof(AccountTier.Registered), result.Data.AccountTier);
        Assert.Equal(user.DisplayName, result.Data.DisplayName);
    }

    // ---- StartEmailRegistrationAsync ----

    [Fact]
    public async Task StartEmailRegistrationAsync_MissingEmailOrPassword_Fails()
    {
        var result = await sut.StartEmailRegistrationAsync(new EmailRegisterRequest { Email = "", Password = "password1" });

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task StartEmailRegistrationAsync_ExistingEmail_ReturnsSyntheticResponse_WithoutPersistingOrEmailing()
    {
        var request = new EmailRegisterRequest { Email = "taken@example.com", Password = "password1" };
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync(User(email: request.Email));

        // No Setup for UpsertPendingEmailVerificationAsync or emailSender.SendAsync -
        // MockBehavior.Strict makes an unexpected call throw, so this also asserts they are never invoked.
        var result = await sut.StartEmailRegistrationAsync(request);

        Assert.True(result.IsSuccess);
        Assert.NotEqual(Guid.Empty, result.Data!.PendingId);
    }

    [Fact]
    public async Task StartEmailRegistrationAsync_NewEmail_PersistsPendingVerificationAndSendsEmail()
    {
        var request = new EmailRegisterRequest { Email = "new@example.com", Password = "password1", DisplayName = "New Guy" };
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.UpsertPendingEmailVerificationAsync(
                It.IsAny<Guid>(), request.ExistingUserId, request.Email, It.IsAny<byte[]>(), It.IsAny<byte[]>(), request.DisplayName,
                It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        emailSender.Setup(e => e.SendAsync(request.Email, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.StartEmailRegistrationAsync(request);

        Assert.True(result.IsSuccess);
        Assert.NotEqual(Guid.Empty, result.Data!.PendingId);
        authProvider.Verify(p => p.UpsertPendingEmailVerificationAsync(
            It.IsAny<Guid>(), request.ExistingUserId, request.Email, It.IsAny<byte[]>(), It.IsAny<byte[]>(), request.DisplayName,
            It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Once);
        emailSender.Verify(e => e.SendAsync(request.Email, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    // ---- VerifyEmailRegistrationAsync ----

    private static PendingEmailVerificationModel Pending(
        Guid? pendingId = null, string code = "123456", DateTime? expiresAtUtc = null, int attemptCount = 0, string email = "new@example.com")
    {
        var (passwordHash, passwordSalt) = PasswordHasher.Hash("password1");
        var (codeHash, codeSalt) = PasswordHasher.Hash(code);

        return new()
        {
            PendingId = pendingId ?? Guid.NewGuid(),
            Email = email,
            PasswordHash = passwordHash,
            PasswordSalt = passwordSalt,
            DisplayName = "New Guy",
            CodeHash = codeHash,
            CodeSalt = codeSalt,
            AttemptCount = attemptCount,
            ExpiresAtUtc = expiresAtUtc ?? DateTime.UtcNow.AddMinutes(10),
            LastSentAtUtc = DateTime.UtcNow
        };
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_PendingNotFound_Fails()
    {
        var pendingId = Guid.NewGuid();
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((PendingEmailVerificationModel?)null);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pendingId, Code = "123456" });

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_Expired_DeletesPendingAndFails()
    {
        var pending = Pending(expiresAtUtc: DateTime.UtcNow.AddMinutes(-1));
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pending.PendingId, Code = "123456" });

        Assert.False(result.IsSuccess);
        authProvider.Verify(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_MaxAttemptsExceeded_DeletesPendingAndFails()
    {
        var pending = Pending(attemptCount: 5);
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pending.PendingId, Code = "123456" });

        Assert.False(result.IsSuccess);
        authProvider.Verify(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_WrongCode_IncrementsAttemptAndFails()
    {
        var pending = Pending(code: "123456");
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.IncrementPendingEmailVerificationAttemptAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pending.PendingId, Code = "999999" });

        Assert.False(result.IsSuccess);
        authProvider.Verify(p => p.IncrementPendingEmailVerificationAttemptAsync(pending.PendingId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_CorrectCode_RegistersMarksVerifiedDeletesPending_AndReturnsToken()
    {
        var pending = Pending(code: "123456");
        var newUserId = Guid.NewGuid();
        var registeredUser = User(userId: newUserId, email: pending.Email);

        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.RegisterEmailUserAsync(
                pending.ExistingUserId, pending.Email, pending.PasswordHash, pending.PasswordSalt, pending.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.MarkEmailVerifiedAsync(newUserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        authProvider.Setup(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(registeredUser);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pending.PendingId, Code = "123456" });

        Assert.True(result.IsSuccess);
        Assert.False(string.IsNullOrWhiteSpace(result.Data!.Token));
        Assert.Equal(newUserId, result.Data.UserId);
        authProvider.Verify(p => p.MarkEmailVerifiedAsync(newUserId, It.IsAny<CancellationToken>()), Times.Once);
        authProvider.Verify(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyEmailRegistrationAsync_ReRegisteredUserCannotBeReRead_Fails()
    {
        var pending = Pending(code: "123456");
        var newUserId = Guid.NewGuid();

        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.RegisterEmailUserAsync(
                pending.ExistingUserId, pending.Email, pending.PasswordHash, pending.PasswordSalt, pending.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.MarkEmailVerifiedAsync(newUserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        authProvider.Setup(p => p.DeletePendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);

        var result = await sut.VerifyEmailRegistrationAsync(new EmailVerificationRequest { PendingId = pending.PendingId, Code = "123456" });

        Assert.False(result.IsSuccess);
    }

    // ---- ResendEmailVerificationAsync ----

    [Fact]
    public async Task ResendEmailVerificationAsync_PendingNotFound_Fails()
    {
        var pendingId = Guid.NewGuid();
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((PendingEmailVerificationModel?)null);

        var result = await sut.ResendEmailVerificationAsync(new ResendEmailVerificationRequest { PendingId = pendingId });

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task ResendEmailVerificationAsync_WithinCooldown_Fails()
    {
        var pending = Pending();
        pending.LastSentAtUtc = DateTime.UtcNow;
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);

        var result = await sut.ResendEmailVerificationAsync(new ResendEmailVerificationRequest { PendingId = pending.PendingId });

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task ResendEmailVerificationAsync_CooldownElapsed_RefreshesAndSendsEmail()
    {
        var pending = Pending();
        pending.LastSentAtUtc = DateTime.UtcNow.AddSeconds(-31);
        authProvider.Setup(p => p.GetPendingEmailVerificationAsync(pending.PendingId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(pending);
        authProvider.Setup(p => p.RefreshPendingEmailVerificationAsync(
                pending.PendingId, It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        emailSender.Setup(e => e.SendAsync(pending.Email, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.ResendEmailVerificationAsync(new ResendEmailVerificationRequest { PendingId = pending.PendingId });

        Assert.True(result.IsSuccess);
        Assert.Equal(pending.PendingId, result.Data!.PendingId);
        authProvider.Verify(p => p.RefreshPendingEmailVerificationAsync(
            pending.PendingId, It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Once);
        emailSender.Verify(e => e.SendAsync(pending.Email, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    // ---- LoginEmailAsync ----

    [Fact]
    public async Task LoginEmailAsync_UserNotFound_Fails()
    {
        var request = new EmailLoginRequest { Email = "missing@example.com", Password = "password1" };
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);

        var result = await sut.LoginEmailAsync(request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginEmailAsync_UserHasNoPasswordSet_Fails()
    {
        var request = new EmailLoginRequest { Email = "google-only@example.com", Password = "password1" };
        var user = User(email: request.Email, passwordHash: null, passwordSalt: null);
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);

        var result = await sut.LoginEmailAsync(request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginEmailAsync_WrongPassword_Fails()
    {
        var (hash, salt) = PasswordHasher.Hash("correct-password");
        var request = new EmailLoginRequest { Email = "user@example.com", Password = "wrong-password" };
        var user = User(email: request.Email, passwordHash: hash, passwordSalt: salt);
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);

        var result = await sut.LoginEmailAsync(request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginEmailAsync_CorrectPassword_UpdatesLastLogin_AndReturnsToken()
    {
        var (hash, salt) = PasswordHasher.Hash("correct-password");
        var request = new EmailLoginRequest { Email = "user@example.com", Password = "correct-password" };
        var user = User(email: request.Email, passwordHash: hash, passwordSalt: salt);
        authProvider.Setup(p => p.GetUserByEmailAsync(request.Email, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(user.UserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginEmailAsync(request);

        Assert.True(result.IsSuccess);
        Assert.False(string.IsNullOrWhiteSpace(result.Data!.Token));
        Assert.Equal(user.UserId, result.Data.UserId);
        authProvider.Verify(p => p.UpdateLastLoginAsync(user.UserId, It.IsAny<CancellationToken>()), Times.Once);
    }

    // ---- LoginOrLinkGoogleAsync ----

    [Fact]
    public async Task LoginOrLinkGoogleAsync_VerifierReturnsNull_Fails()
    {
        var request = new GoogleLoginRequest { IdToken = "bad-token" };
        googleTokenVerifier.Setup(v => v.VerifyAsync(request.IdToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ExternalIdentityPayload?)null);

        var result = await sut.LoginOrLinkGoogleAsync(request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginOrLinkGoogleAsync_ExistingIdentity_UsesItsUserId_DoesNotLink()
    {
        var request = new GoogleLoginRequest { IdToken = "good-token" };
        var payload = new ExternalIdentityPayload { Subject = "google-sub-1", Email = "g@example.com", DisplayName = "G User" };
        var existingIdentityUser = User(email: payload.Email);
        var user = User(userId: existingIdentityUser.UserId, email: payload.Email);

        googleTokenVerifier.Setup(v => v.VerifyAsync(request.IdToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Google", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync(existingIdentityUser);
        authProvider.Setup(p => p.GetUserByIdAsync(existingIdentityUser.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(user.UserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginOrLinkGoogleAsync(request);

        Assert.True(result.IsSuccess);
        Assert.Equal(user.UserId, result.Data!.UserId);
        authProvider.Verify(p => p.LinkExternalIdentityAsync(
            It.IsAny<Guid?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task LoginOrLinkGoogleAsync_NoExistingIdentity_LinksNewIdentity()
    {
        var request = new GoogleLoginRequest { ExistingUserId = Guid.NewGuid(), IdToken = "good-token" };
        var payload = new ExternalIdentityPayload { Subject = "google-sub-2", Email = "g2@example.com", DisplayName = "G2 User" };
        var newUserId = Guid.NewGuid();
        var user = User(userId: newUserId, email: payload.Email);

        googleTokenVerifier.Setup(v => v.VerifyAsync(request.IdToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Google", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.LinkExternalIdentityAsync(
                request.ExistingUserId, "Google", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(newUserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginOrLinkGoogleAsync(request);

        Assert.True(result.IsSuccess);
        Assert.Equal(newUserId, result.Data!.UserId);
        authProvider.Verify(p => p.LinkExternalIdentityAsync(
            request.ExistingUserId, "Google", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task LoginOrLinkGoogleAsync_LinkedUserCannotBeReRead_Fails()
    {
        var request = new GoogleLoginRequest { IdToken = "good-token" };
        var payload = new ExternalIdentityPayload { Subject = "google-sub-3", Email = "g3@example.com", DisplayName = "G3 User" };
        var newUserId = Guid.NewGuid();

        googleTokenVerifier.Setup(v => v.VerifyAsync(request.IdToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Google", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.LinkExternalIdentityAsync(
                request.ExistingUserId, "Google", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);

        var result = await sut.LoginOrLinkGoogleAsync(request);

        Assert.False(result.IsSuccess);
    }

    // ---- LoginOrLinkAppleAsync ----

    [Fact]
    public async Task LoginOrLinkAppleAsync_VerifierReturnsNull_Fails()
    {
        var request = new AppleLoginRequest { IdentityToken = "bad-token" };
        appleTokenVerifier.Setup(v => v.VerifyAsync(request.IdentityToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ExternalIdentityPayload?)null);

        var result = await sut.LoginOrLinkAppleAsync(request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task LoginOrLinkAppleAsync_ExistingIdentity_UsesItsUserId_DoesNotLink()
    {
        var request = new AppleLoginRequest { IdentityToken = "good-token" };
        var payload = new ExternalIdentityPayload { Subject = "apple-sub-1", Email = "a@example.com", DisplayName = "A User" };
        var existingIdentityUser = User(email: payload.Email);
        var user = User(userId: existingIdentityUser.UserId, email: payload.Email);

        appleTokenVerifier.Setup(v => v.VerifyAsync(request.IdentityToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Apple", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync(existingIdentityUser);
        authProvider.Setup(p => p.GetUserByIdAsync(existingIdentityUser.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(user.UserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginOrLinkAppleAsync(request);

        Assert.True(result.IsSuccess);
        Assert.Equal(user.UserId, result.Data!.UserId);
        authProvider.Verify(p => p.LinkExternalIdentityAsync(
            It.IsAny<Guid?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task LoginOrLinkAppleAsync_NoExistingIdentity_LinksNewIdentity_UsingPayloadDisplayNameWhenRequestHasNone()
    {
        var request = new AppleLoginRequest { ExistingUserId = Guid.NewGuid(), IdentityToken = "good-token", DisplayName = null };
        var payload = new ExternalIdentityPayload { Subject = "apple-sub-2", Email = "a2@example.com", DisplayName = "Payload Name" };
        var newUserId = Guid.NewGuid();
        var user = User(userId: newUserId, email: payload.Email);

        appleTokenVerifier.Setup(v => v.VerifyAsync(request.IdentityToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Apple", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.LinkExternalIdentityAsync(
                request.ExistingUserId, "Apple", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(newUserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginOrLinkAppleAsync(request);

        Assert.True(result.IsSuccess);
        authProvider.Verify(p => p.LinkExternalIdentityAsync(
            request.ExistingUserId, "Apple", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task LoginOrLinkAppleAsync_RequestDisplayName_TakesPrecedenceOverPayloadDisplayName()
    {
        var request = new AppleLoginRequest { IdentityToken = "good-token", DisplayName = "Request Name" };
        var payload = new ExternalIdentityPayload { Subject = "apple-sub-3", Email = "a3@example.com", DisplayName = "Payload Name" };
        var newUserId = Guid.NewGuid();
        var user = User(userId: newUserId, email: payload.Email);

        appleTokenVerifier.Setup(v => v.VerifyAsync(request.IdentityToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Apple", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.LinkExternalIdentityAsync(
                request.ExistingUserId, "Apple", payload.Subject, payload.Email, "Request Name", It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(user);
        authProvider.Setup(p => p.UpdateLastLoginAsync(newUserId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.LoginOrLinkAppleAsync(request);

        Assert.True(result.IsSuccess);
        authProvider.Verify(p => p.LinkExternalIdentityAsync(
            request.ExistingUserId, "Apple", payload.Subject, payload.Email, "Request Name", It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task LoginOrLinkAppleAsync_LinkedUserCannotBeReRead_Fails()
    {
        var request = new AppleLoginRequest { IdentityToken = "good-token" };
        var payload = new ExternalIdentityPayload { Subject = "apple-sub-4", Email = "a4@example.com", DisplayName = "A4 User" };
        var newUserId = Guid.NewGuid();

        appleTokenVerifier.Setup(v => v.VerifyAsync(request.IdentityToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(payload);
        authProvider.Setup(p => p.GetIdentityAsync("Apple", payload.Subject, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);
        authProvider.Setup(p => p.LinkExternalIdentityAsync(
                request.ExistingUserId, "Apple", payload.Subject, payload.Email, payload.DisplayName, It.IsAny<CancellationToken>()))
            .ReturnsAsync(newUserId);
        authProvider.Setup(p => p.GetUserByIdAsync(newUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserAccountModel?)null);

        var result = await sut.LoginOrLinkAppleAsync(request);

        Assert.False(result.IsSuccess);
    }
}
