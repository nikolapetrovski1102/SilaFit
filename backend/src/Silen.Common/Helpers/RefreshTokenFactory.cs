using System.Security.Cryptography;
using System.Text;

namespace Silen.Common.Helpers;

/// <summary>
/// Mints the opaque refresh tokens handed out with every app session and hashes
/// them for storage. Only the SHA-256 ever reaches the database, so a leaked
/// table can't be replayed. A plain hash (no salt/PBKDF2) is enough here: the
/// token is 256 random bits, not a guessable password, and the hash has to be
/// an exact lookup key.
/// </summary>
public static class RefreshTokenFactory
{
    public static string Create() => Base64UrlEncode(RandomNumberGenerator.GetBytes(32));

    public static byte[] Hash(string refreshToken) => SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken));

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
