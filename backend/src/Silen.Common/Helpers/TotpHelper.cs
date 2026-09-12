using System.Security.Cryptography;

namespace Silen.Common.Helpers;

/// <summary>
/// RFC 6238 TOTP - the rotating 6-digit code an authenticator app shows. This is
/// the console's second factor, so the account's password alone can never open
/// the dashboard.
///
/// SHA-1 is the hash here on purpose: RFC 6238's SHA-1 mode is what every
/// authenticator app (Google Authenticator, Authy, 1Password, ...) assumes when a
/// secret is scanned, and because the hash is used inside an HMAC the usual
/// collision concerns don't apply. Don't "upgrade" this without also changing the
/// algorithm= parameter in <see cref="BuildOtpAuthUri"/>.
/// </summary>
public static class TotpHelper
{
    /// <summary>160-bit secrets - the size RFC 4226 recommends and what other apps generate.</summary>
    private const int SecretSizeBytes = 20;

    /// <summary>Creates a fresh base32 secret for one account (enrollment / rotation).</summary>
    public static string GenerateSecret() => Base32Helper.Encode(RandomNumberGenerator.GetBytes(SecretSizeBytes));

    /// <summary>
    /// The URI an authenticator app encodes into its QR code. Kept unpadded and
    /// SHA-1/6/30 explicit so any scanner lands on the same settings.
    /// </summary>
    public static string BuildOtpAuthUri(string issuer, string accountName, string secret, int digits, int stepSeconds) =>
        $"otpauth://totp/{Uri.EscapeDataString(issuer)}:{Uri.EscapeDataString(accountName)}" +
        $"?secret={Uri.EscapeDataString(secret)}" +
        $"&issuer={Uri.EscapeDataString(issuer)}" +
        "&algorithm=SHA1" +
        $"&digits={digits}" +
        $"&period={stepSeconds}";

    /// <summary>The code valid at <paramref name="utcNow"/> - used by tests and by the provisioning tool to prove enrollment worked.</summary>
    public static string ComputeCode(string secret, DateTime utcNow, int digits, int stepSeconds) =>
        ComputeCodeForCounter(Base32Helper.Decode(secret), CounterFor(utcNow, stepSeconds), digits);

    /// <summary>
    /// Verifies a typed code. <paramref name="windowSteps"/> tolerates clock drift
    /// and the second or two it takes to read the code off the phone; 1 means the
    /// previous and next step are also accepted.
    /// </summary>
    public static bool VerifyCode(
        string secret,
        string? code,
        DateTime utcNow,
        int digits,
        int stepSeconds,
        int windowSteps)
    {
        var trimmed = code?.Trim();
        if (string.IsNullOrEmpty(trimmed) || trimmed.Length != digits || !trimmed.All(char.IsAsciiDigit))
        {
            return false;
        }

        var secretBytes = Base32Helper.Decode(secret);
        var counter = CounterFor(utcNow, stepSeconds);

        for (var offset = -windowSteps; offset <= windowSteps; offset++)
        {
            if (FixedTimeEquals(ComputeCodeForCounter(secretBytes, counter + offset, digits), trimmed))
            {
                return true;
            }
        }

        return false;
    }

    private static long CounterFor(DateTime utcNow, int stepSeconds) =>
        (long)(utcNow - DateTime.UnixEpoch).TotalSeconds / stepSeconds;

    private static string ComputeCodeForCounter(byte[] secretBytes, long counter, int digits)
    {
        var counterBytes = BitConverter.GetBytes(counter);
        if (BitConverter.IsLittleEndian)
        {
            Array.Reverse(counterBytes);
        }

        using var hmac = new HMACSHA1(secretBytes);
        var hash = hmac.ComputeHash(counterBytes);

        // Dynamic truncation (RFC 4226 §5.3): the low nibble of the last byte picks
        // the 4-byte window, and the top bit is masked off so the result is unsigned.
        var offset = hash[^1] & 0x0F;
        var binary = ((hash[offset] & 0x7F) << 24)
                     | ((hash[offset + 1] & 0xFF) << 16)
                     | ((hash[offset + 2] & 0xFF) << 8)
                     | (hash[offset + 3] & 0xFF);

        var modulus = 1;
        for (var i = 0; i < digits; i++)
        {
            modulus *= 10;
        }

        return (binary % modulus).ToString().PadLeft(digits, '0');
    }

    /// <summary>Fixed-time compare so a wrong code doesn't leak how many leading digits were right.</summary>
    private static bool FixedTimeEquals(string left, string right) =>
        CryptographicOperations.FixedTimeEquals(
            System.Text.Encoding.ASCII.GetBytes(left),
            System.Text.Encoding.ASCII.GetBytes(right));
}
