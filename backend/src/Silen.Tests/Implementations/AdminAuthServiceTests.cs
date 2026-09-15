using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AdminAuthServiceTests
{
    private readonly Mock<IAdminProvider> adminProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminRbacProvider> adminRbacProvider = new(MockBehavior.Strict);
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly byte[] masterKey = RandomNumberGenerator.GetBytes(FieldCipher.KeySizeBytes);
    private readonly AdminAuthService sut;

    private const string InvalidCredentialsMessage = "Invalid username or password.";

    public AdminAuthServiceTests()
    {
        sut = new AdminAuthService(
            adminProvider.Object,
            adminRbacProvider.Object,
            emailSender.Object,
            Options.Create(AuthOptions()),
            Options.Create(JwtOptionsValue()),
            Options.Create(new EncryptionOptions { MasterKeyBase64 = Convert.ToBase64String(masterKey) }));
    }

    private static AdminAuthOptions AuthOptions() => new()
    {
        LockoutThreshold = 5,
        LockoutMinutes = 15,
        ChallengeMinutes = 5,
        SessionIdleMinutes = 30,
        SessionAbsoluteMinutes = 480,
        TotpIssuer = "Test Admin",
        TotpDigits = 6,
        TotpStepSeconds = 30,
        TotpWindowSteps = 1
    };

    private static JwtOptions JwtOptionsValue() => new()
    {
        Issuer = "silen-tests",
        Audience = "silen-admin",
        SigningKey = "unit-test-signing-key-at-least-256-bits-long!!",
        ExpiryMinutes = 60
    };

    private AdminAccountModel Account(
        string username = "ops-admin",
        string password = "correct-password",
        bool isActive = true,
        DateTime? lockedUntilUtc = null,
        string? totpSecret = null,
        string? email = null,
        DateTime? emailOtpLastSentAtUtc = null)
    {
        var (hash, salt) = PasswordHasher.Hash(password);
        var secret = totpSecret ?? TotpHelper.GenerateSecret();
        return new AdminAccountModel
        {
            AdminUserId = Guid.NewGuid(),
            Username = username,
            PasswordHash = hash,
            PasswordSalt = salt,
            TotpSecretCipher = AdminTotpSecretCipher.Encrypt(secret, masterKey),
            IsActive = isActive,
            LockedUntilUtc = lockedUntilUtc,
            RoleName = "Operator",
            Email = email,
            EmailOtpLastSentAtUtc = emailOtpLastSentAtUtc
        };
    }

    /// <summary>Stamps an emailed one-time code onto the account the same way
    /// <see cref="AdminEmailOtpValidator"/> expects to find it.</summary>
    private static (AdminAccountModel Account, string Code) WithEmailOtp(AdminAccountModel account, TimeSpan? expiresIn = null)
    {
        var code = VerificationCodeGenerator.GenerateCode();
        var (hash, salt) = PasswordHasher.Hash(code);
        account.EmailOtpCodeHash = hash;
        account.EmailOtpCodeSalt = salt;
        account.EmailOtpExpiresAtUtc = DateTime.UtcNow.Add(expiresIn ?? TimeSpan.FromMinutes(10));
        return (account, code);
    }

    private static string Challenge(Guid adminUserId, string username, int minutes = 5) =>
        AdminChallengeTokenFactory.CreateChallenge(JwtOptionsValue(), adminUserId, username, TimeSpan.FromMinutes(minutes));

    /* ------------------------------- StartLoginAsync ------------------------------ */

    [Fact]
    public async Task StartLoginAsync_BlankUsername_ReturnsValidationFailure()
    {
        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = "  ", Password = "whatever" });

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task StartLoginAsync_BlankPassword_ReturnsValidationFailure()
    {
        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = "ops-admin", Password = " " });

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task StartLoginAsync_UnknownUsername_ReturnsGenericInvalidCredentialsMessage()
    {
        adminProvider.Setup(p => p.GetAccountByUsernameAsync("ghost", It.IsAny<CancellationToken>())).ReturnsAsync((AdminAccountModel?)null);

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = "ghost", Password = "anything" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        Assert.Equal(InvalidCredentialsMessage, result.UserMessage);
    }

    [Fact]
    public async Task StartLoginAsync_InactiveAccount_ReturnsSameGenericMessageAsUnknownUsername()
    {
        var account = Account(isActive: false);
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = account.Username, Password = "correct-password" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        Assert.Equal(InvalidCredentialsMessage, result.UserMessage);
    }

    [Fact]
    public async Task StartLoginAsync_AccountLocked_ReturnsTooManyRequestsFailureBeforeCheckingPassword()
    {
        var account = Account(lockedUntilUtc: DateTime.UtcNow.AddMinutes(10));
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = account.Username, Password = "totally-wrong" });

        Assert.False(result.IsSuccess);
        Assert.Equal(429, result.StatusCode);
    }

    [Fact]
    public async Task StartLoginAsync_WrongPassword_RecordsFailureAndReturnsGenericMessage()
    {
        var account = Account();
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminLockoutStateModel { FailedAttemptCount = 1, LockedUntilUtc = null });

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = account.Username, Password = "wrong-password" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        Assert.Equal(InvalidCredentialsMessage, result.UserMessage);
        adminProvider.Verify(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task StartLoginAsync_WrongPassword_TripsLockoutThreshold_Returns429()
    {
        var account = Account();
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminLockoutStateModel { FailedAttemptCount = 5, LockedUntilUtc = DateTime.UtcNow.AddMinutes(15) });

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = account.Username, Password = "wrong-password" });

        Assert.False(result.IsSuccess);
        Assert.Equal(429, result.StatusCode);
        Assert.Contains("locked", result.UserMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StartLoginAsync_CorrectPassword_ReturnsAReadableChallengeForTheAccount()
    {
        var account = Account();
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = account.Username, Password = "correct-password" });

        Assert.True(result.IsSuccess);
        Assert.Equal(300, result.Data!.ExpiresInSeconds);
        var challenge = AdminChallengeTokenFactory.ReadChallenge(JwtOptionsValue(), result.Data.ChallengeToken);
        Assert.NotNull(challenge);
        Assert.Equal(account.AdminUserId, challenge!.AdminUserId);
        Assert.Equal(account.Username, challenge.Username);
    }

    [Fact]
    public async Task StartLoginAsync_TrimsWhitespaceFromUsernameBeforeLookup()
    {
        var account = Account();
        adminProvider.Setup(p => p.GetAccountByUsernameAsync(account.Username, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.StartLoginAsync(new AdminLoginRequest { Username = $"  {account.Username}  ", Password = "correct-password" });

        Assert.True(result.IsSuccess);
    }

    /* ------------------------------- VerifyCodeAsync ------------------------------ */

    [Fact]
    public async Task VerifyCodeAsync_GarbageChallengeToken_ReturnsUnauthorizedFailure()
    {
        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = "not-a-jwt", Code = "123456" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task VerifyCodeAsync_ExpiredChallenge_ReturnsUnauthorizedFailure()
    {
        var expired = Challenge(Guid.NewGuid(), "ops-admin", minutes: -5);

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = expired, Code = "123456" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task VerifyCodeAsync_AccountNoLongerActive_ReturnsGenericInvalidCredentialsMessage()
    {
        var adminUserId = Guid.NewGuid();
        var token = Challenge(adminUserId, "ops-admin");
        adminProvider.Setup(p => p.GetAccountByIdAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync((AdminAccountModel?)null);

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = "123456" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        Assert.Equal(InvalidCredentialsMessage, result.UserMessage);
    }

    [Fact]
    public async Task VerifyCodeAsync_AccountLockedBetweenSteps_Returns429()
    {
        var account = Account(lockedUntilUtc: DateTime.UtcNow.AddMinutes(10));
        var token = Challenge(account.AdminUserId, account.Username);
        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = "123456" });

        Assert.False(result.IsSuccess);
        Assert.Equal(429, result.StatusCode);
    }

    [Fact]
    public async Task VerifyCodeAsync_WrongCode_RecordsFailureAndReturnsFailure()
    {
        var secret = TotpHelper.GenerateSecret();
        var account = Account(totpSecret: secret);
        var token = Challenge(account.AdminUserId, account.Username);
        var wrongCode = TotpHelper.ComputeCode(secret, DateTime.UtcNow.AddMinutes(10), 6, 30);

        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminLockoutStateModel { FailedAttemptCount = 1, LockedUntilUtc = null });

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = wrongCode });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        adminProvider.Verify(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyCodeAsync_CorrectCode_IssuesSessionAndPersistsOnlyTheHashedToken()
    {
        var secret = TotpHelper.GenerateSecret();
        var account = Account(totpSecret: secret);
        var token = Challenge(account.AdminUserId, account.Username);
        var code = TotpHelper.ComputeCode(secret, DateTime.UtcNow, 6, 30);

        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordSuccessfulLoginAsync(account.AdminUserId, It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);

        byte[]? persistedHash = null;
        adminProvider.Setup(p => p.CreateSessionAsync(
                account.AdminUserId, It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<DateTime>(), "203.0.113.5", It.IsAny<CancellationToken>()))
            .Callback<Guid, byte[], DateTime, DateTime, string?, CancellationToken>((_, hash, _, _, _, _) => persistedHash = hash)
            .ReturnsAsync(Guid.NewGuid());

        adminRbacProvider.Setup(p => p.GetPermissionsAsync(account.AdminUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(["content.plans.read"]);

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = code, ClientIp = "203.0.113.5" });

        Assert.True(result.IsSuccess);
        Assert.Equal(account.Username, result.Data!.Username);
        Assert.Equal(["content.plans.read"], result.Data.Permissions);
        Assert.NotNull(persistedHash);
        Assert.Equal(AdminSessionTokenFactory.HashToken(result.Data.Token), persistedHash);
        adminProvider.Verify(p => p.RecordSuccessfulLoginAsync(account.AdminUserId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyCodeAsync_CorrectEmailCode_SucceedsEvenThoughItIsNotAValidTotpCode()
    {
        var account = Account(email: "ops@example.com");
        var (_, code) = WithEmailOtp(account);
        var token = Challenge(account.AdminUserId, account.Username);

        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordSuccessfulLoginAsync(account.AdminUserId, It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
        adminProvider.Setup(p => p.CreateSessionAsync(
                account.AdminUserId, It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<DateTime>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Guid.NewGuid());
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync([]);

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = code });

        Assert.True(result.IsSuccess);
        adminProvider.Verify(p => p.RecordSuccessfulLoginAsync(account.AdminUserId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyCodeAsync_ExpiredEmailCode_RecordsFailureLikeAnyWrongCode()
    {
        var account = Account(email: "ops@example.com");
        var (_, code) = WithEmailOtp(account, expiresIn: TimeSpan.FromMinutes(-1));
        var token = Challenge(account.AdminUserId, account.Username);

        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminLockoutStateModel { FailedAttemptCount = 1, LockedUntilUtc = null });

        var result = await sut.VerifyCodeAsync(new AdminVerifyCodeRequest { ChallengeToken = token, Code = code });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
        adminProvider.Verify(p => p.RecordFailedLoginAsync(account.AdminUserId, 5, 15, It.IsAny<CancellationToken>()), Times.Once);
    }

    /* ------------------------------- SendEmailCodeAsync ------------------------------ */

    [Fact]
    public async Task SendEmailCodeAsync_GarbageChallengeToken_ReturnsUnauthorizedFailure()
    {
        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = "not-a-jwt" });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task SendEmailCodeAsync_AccountNoLongerActive_ReturnsUnauthorizedFailure()
    {
        var adminUserId = Guid.NewGuid();
        var token = Challenge(adminUserId, "ops-admin");
        adminProvider.Setup(p => p.GetAccountByIdAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync((AdminAccountModel?)null);

        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = token });

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task SendEmailCodeAsync_AccountLocked_Returns429()
    {
        var account = Account(lockedUntilUtc: DateTime.UtcNow.AddMinutes(10), email: "ops@example.com");
        var token = Challenge(account.AdminUserId, account.Username);
        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = token });

        Assert.False(result.IsSuccess);
        Assert.Equal(429, result.StatusCode);
    }

    [Fact]
    public async Task SendEmailCodeAsync_NoEmailOnFile_ReturnsValidationFailure()
    {
        var account = Account(email: null);
        var token = Challenge(account.AdminUserId, account.Username);
        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = token });

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SendEmailCodeAsync_RequestedTooSoonAfterPreviousSend_ReturnsConflict()
    {
        var account = Account(email: "ops@example.com", emailOtpLastSentAtUtc: DateTime.UtcNow.AddSeconds(-5));
        var token = Challenge(account.AdminUserId, account.Username);
        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);

        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = token });

        Assert.False(result.IsSuccess);
        Assert.Equal(409, result.StatusCode);
    }

    [Fact]
    public async Task SendEmailCodeAsync_HasEmailOnFile_StoresHashedCodeAndSendsIt()
    {
        var account = Account(email: "ops@example.com");
        var token = Challenge(account.AdminUserId, account.Username);
        adminProvider.Setup(p => p.GetAccountByIdAsync(account.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminProvider.Setup(p => p.SetEmailOtpAsync(
                account.AdminUserId, account.Email!, It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        emailSender.Setup(e => e.SendAsync(account.Email!, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.SendEmailCodeAsync(new AdminSendEmailCodeRequest { ChallengeToken = token });

        Assert.True(result.IsSuccess);
        Assert.Equal("o***@example.com", result.Data!.MaskedEmail);
        Assert.Equal(600, result.Data.ExpiresInSeconds);
        adminProvider.Verify(p => p.SetEmailOtpAsync(
            account.AdminUserId, account.Email!, It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Once);
        emailSender.Verify(e => e.SendAsync(account.Email!, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    /* ------------------------------- GetSessionAsync ------------------------------ */

    [Fact]
    public async Task GetSessionAsync_NoCookie_ReturnsUnauthorizedFailure()
    {
        var result = await sut.GetSessionAsync(null);

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task GetSessionAsync_TokenDoesNotResolve_ReturnsUnauthorizedFailure()
    {
        adminProvider.Setup(p => p.GetSessionAsync(It.IsAny<byte[]>(), It.IsAny<CancellationToken>())).ReturnsAsync((AdminSessionModel?)null);

        var result = await sut.GetSessionAsync("some-cookie-value");

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task GetSessionAsync_WithinIdleWindow_TouchesSessionAndReturnsRoleAndPermissions()
    {
        var sessionToken = AdminSessionTokenFactory.CreateToken();
        var session = new AdminSessionModel
        {
            AdminSessionId = Guid.NewGuid(),
            AdminUserId = Guid.NewGuid(),
            Username = "ops-admin",
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(10),
            AbsoluteExpiresAtUtc = DateTime.UtcNow.AddHours(6),
            LastSeenAtUtc = DateTime.UtcNow
        };
        var account = Account(username: session.Username);
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).ReturnsAsync(session);
        adminProvider.Setup(p => p.TouchSessionAsync(session.AdminSessionId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
        adminProvider.Setup(p => p.GetAccountByIdAsync(session.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(account);
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(session.AdminUserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(["content.plans.read"]);

        var result = await sut.GetSessionAsync(sessionToken);

        Assert.True(result.IsSuccess);
        Assert.Equal(session.Username, result.Data!.Username);
        Assert.Equal(account.RoleName, result.Data.RoleName);
        Assert.True(result.Data.ExpiresAtUtc <= session.AbsoluteExpiresAtUtc);
        adminProvider.Verify(p => p.TouchSessionAsync(session.AdminSessionId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetSessionAsync_SlidingIdleWindowWouldExceedAbsoluteCap_ClampsToAbsoluteExpiry()
    {
        var sessionToken = AdminSessionTokenFactory.CreateToken();
        var absoluteExpiry = DateTime.UtcNow.AddMinutes(10); // sooner than the 30-minute idle slide
        var session = new AdminSessionModel
        {
            AdminSessionId = Guid.NewGuid(),
            AdminUserId = Guid.NewGuid(),
            Username = "ops-admin",
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(5),
            AbsoluteExpiresAtUtc = absoluteExpiry,
            LastSeenAtUtc = DateTime.UtcNow
        };
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).ReturnsAsync(session);
        adminProvider.Setup(p => p.TouchSessionAsync(session.AdminSessionId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);
        adminProvider.Setup(p => p.GetAccountByIdAsync(session.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync((AdminAccountModel?)null);
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(session.AdminUserId, It.IsAny<CancellationToken>())).ReturnsAsync([]);

        var result = await sut.GetSessionAsync(sessionToken);

        Assert.True(result.IsSuccess);
        Assert.Equal(absoluteExpiry, result.Data!.ExpiresAtUtc);
        Assert.Null(result.Data.RoleName);
    }

    /* ------------------------------- SignOutAsync / SignOutEverywhereAsync ------------------------------ */

    [Fact]
    public async Task SignOutAsync_WithToken_DeletesTheHashedSession()
    {
        var sessionToken = AdminSessionTokenFactory.CreateToken();
        adminProvider.Setup(p => p.DeleteSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);

        var result = await sut.SignOutAsync(sessionToken);

        Assert.True(result.IsSuccess);
        Assert.True(result.Data);
        adminProvider.Verify(p => p.DeleteSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task SignOutAsync_NoToken_IsANoOpAndStillSucceeds()
    {
        var result = await sut.SignOutAsync(null);

        Assert.True(result.IsSuccess);
        Assert.True(result.Data);
    }

    [Fact]
    public async Task SignOutEverywhereAsync_ResolvesSessionAndDeletesEverySessionForThatOperator()
    {
        var sessionToken = AdminSessionTokenFactory.CreateToken();
        var session = new AdminSessionModel
        {
            AdminSessionId = Guid.NewGuid(),
            AdminUserId = Guid.NewGuid(),
            Username = "ops-admin",
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(10),
            AbsoluteExpiresAtUtc = DateTime.UtcNow.AddHours(6),
            LastSeenAtUtc = DateTime.UtcNow
        };
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).ReturnsAsync(session);
        adminProvider.Setup(p => p.DeleteAllSessionsAsync(session.AdminUserId, It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);

        var result = await sut.SignOutEverywhereAsync(sessionToken);

        Assert.True(result.IsSuccess);
        adminProvider.Verify(p => p.DeleteAllSessionsAsync(session.AdminUserId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task SignOutEverywhereAsync_NoToken_ReturnsUnauthorizedFailure()
    {
        var result = await sut.SignOutEverywhereAsync(null);

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }
}
