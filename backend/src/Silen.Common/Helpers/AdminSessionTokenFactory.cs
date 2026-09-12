using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace Silen.Common.Helpers;

/// <summary>
/// Mints and hashes the opaque cookie token that identifies a console session.
///
/// The browser gets 32 random bytes (base64url); only the SHA-256 of that string is
/// stored, so the AdminSessions table on its own can't be replayed. It is not a JWT
/// on purpose - being server-side state is exactly what makes sign-out and the
/// idle/absolute expiry enforceable instead of merely advisory.
/// </summary>
public static class AdminSessionTokenFactory
{
    private const int TokenSizeBytes = 32;

    public static string CreateToken() =>
        Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(TokenSizeBytes));

    public static byte[] HashToken(string token) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(token));
}
