using System.Security.Cryptography;

namespace Silen.Common.Helpers;

/// <summary>
/// Generates the 6-digit numeric codes used by the email-registration
/// verification step. Hashing/verifying a generated code reuses
/// <see cref="PasswordHasher"/> rather than a second hashing scheme.
/// </summary>
public static class VerificationCodeGenerator
{
    public static string GenerateCode() => RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
}
