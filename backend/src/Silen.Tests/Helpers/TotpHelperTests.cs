using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class TotpHelperTests
{
    private const int Digits = 6;
    private const int StepSeconds = 30;

    // Fixed reference instant, well clear of a step boundary, so step-drift math
    // in the window tests is deterministic regardless of when the suite runs.
    private static readonly DateTime ReferenceTime = new(2026, 1, 1, 0, 0, 15, DateTimeKind.Utc);

    [Fact]
    public void GenerateSecret_ProducesA160BitBase32Secret()
    {
        var secret = TotpHelper.GenerateSecret();

        var decoded = Base32Helper.Decode(secret);
        Assert.Equal(20, decoded.Length);
    }

    [Fact]
    public void ComputeCode_IsDeterministicForTheSameSecretAndTime()
    {
        var secret = TotpHelper.GenerateSecret();

        var first = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);
        var second = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);

        Assert.Equal(first, second);
        Assert.Equal(Digits, first.Length);
        Assert.All(first, c => Assert.True(char.IsAsciiDigit(c)));
    }

    [Fact]
    public void ComputeCode_DifferentSecrets_ProduceDifferentCodes()
    {
        var codeA = TotpHelper.ComputeCode(TotpHelper.GenerateSecret(), ReferenceTime, Digits, StepSeconds);
        var codeB = TotpHelper.ComputeCode(TotpHelper.GenerateSecret(), ReferenceTime, Digits, StepSeconds);

        // Astronomically unlikely to collide across two random 160-bit secrets.
        Assert.NotEqual(codeA, codeB);
    }

    [Fact]
    public void VerifyCode_ExactCodeAtSameStep_ReturnsTrue()
    {
        var secret = TotpHelper.GenerateSecret();
        var code = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);

        Assert.True(TotpHelper.VerifyCode(secret, code, ReferenceTime, Digits, StepSeconds, windowSteps: 0));
    }

    [Fact]
    public void VerifyCode_WrongCode_ReturnsFalse()
    {
        var secret = TotpHelper.GenerateSecret();
        var code = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);
        var wrongCode = ((int.Parse(code) + 1) % 1_000_000).ToString("D6");

        Assert.False(TotpHelper.VerifyCode(secret, wrongCode, ReferenceTime, Digits, StepSeconds, windowSteps: 0));
    }

    [Fact]
    public void VerifyCode_OneStepDrift_ToleratedWithinWindow()
    {
        var secret = TotpHelper.GenerateSecret();
        var code = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);
        var oneStepLater = ReferenceTime.AddSeconds(StepSeconds);

        Assert.True(TotpHelper.VerifyCode(secret, code, oneStepLater, Digits, StepSeconds, windowSteps: 1));
    }

    [Fact]
    public void VerifyCode_DriftBeyondWindow_IsRejected()
    {
        var secret = TotpHelper.GenerateSecret();
        var code = TotpHelper.ComputeCode(secret, ReferenceTime, Digits, StepSeconds);
        var threeStepsLater = ReferenceTime.AddSeconds(StepSeconds * 3);

        Assert.False(TotpHelper.VerifyCode(secret, code, threeStepsLater, Digits, StepSeconds, windowSteps: 1));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("12345")]   // too short
    [InlineData("1234567")] // too long
    [InlineData("12345a")]  // non-digit
    public void VerifyCode_MalformedInput_ReturnsFalseWithoutThrowing(string? malformed)
    {
        var secret = TotpHelper.GenerateSecret();

        Assert.False(TotpHelper.VerifyCode(secret, malformed, ReferenceTime, Digits, StepSeconds, windowSteps: 1));
    }

    [Fact]
    public void BuildOtpAuthUri_EncodesIssuerAccountAndAlgorithmParameters()
    {
        var uri = TotpHelper.BuildOtpAuthUri("Silen Admin", "ops@silen.app", "JBSWY3DPEHPK3PXP", Digits, StepSeconds);

        Assert.StartsWith("otpauth://totp/Silen%20Admin:ops%40silen.app", uri);
        Assert.Contains("secret=JBSWY3DPEHPK3PXP", uri);
        Assert.Contains("algorithm=SHA1", uri);
        Assert.Contains("digits=6", uri);
        Assert.Contains("period=30", uri);
    }
}
