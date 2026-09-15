using System.Security.Cryptography;
using System.Text;

namespace Silen.Common.Helpers;

/// <summary>
/// Turns identifiers that should not appear verbatim in logs (emails, device ids,
/// usernames, push tokens) into a short, stable, one-way tag. The service logic
/// still sees the real value; only the log line is redacted. A support engineer can
/// still correlate repeated failures by the same actor, but the log never becomes a
/// plaintext store of PII.
/// </summary>
public static class LogRedaction
{
    /// <summary>8 hex chars of a SHA-256 of the trimmed, case-folded value.</summary>
    public static string Tag(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "none";
        }

        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value.Trim().ToLowerInvariant()));
        return Convert.ToHexString(bytes.AsSpan(0, 4)).ToLowerInvariant();
    }
}
