using System.Security.Cryptography;
using System.Text;

namespace Silen.Common.Helpers;

/// <summary>
/// End-to-end encryption of the partner website's request and response payloads. AES-256-GCM with the
/// shared PartnerOptions.PayloadKeyBase64 key. The wire format is one base64url string
/// (standard base64 is accepted too):
///
///   [12-byte nonce][ciphertext][16-byte tag]
///
/// The associated data is "silafit-partner:" + the purpose ("provision", "cancel", and
/// "provision-response" / "cancel-response" for what SilaFit sends back), so a payload
/// sealed for one endpoint or direction fails authentication everywhere else.
/// </summary>
public static class PartnerPayloadCipher
{
    public const string ProvisionPurpose = "provision";
    public const string CancelPurpose = "cancel";
    public const string ProvisionResponsePurpose = "provision-response";
    public const string CancelResponsePurpose = "cancel-response";

    private const int NonceSizeBytes = 12;
    private const int TagSizeBytes = 16;
    private const string AssociatedDataPrefix = "silafit-partner:";

    public static string Encrypt(string plaintext, byte[] key, string purpose)
    {
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var nonce = RandomNumberGenerator.GetBytes(NonceSizeBytes);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[TagSizeBytes];

        using (var aesGcm = new AesGcm(key, TagSizeBytes))
        {
            aesGcm.Encrypt(nonce, plaintextBytes, ciphertext, tag, AssociatedData(purpose));
        }

        var payload = new byte[NonceSizeBytes + ciphertext.Length + TagSizeBytes];
        Buffer.BlockCopy(nonce, 0, payload, 0, NonceSizeBytes);
        Buffer.BlockCopy(ciphertext, 0, payload, NonceSizeBytes, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, payload, NonceSizeBytes + ciphertext.Length, TagSizeBytes);

        return Convert.ToBase64String(payload).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    /// <summary>The decrypted plaintext, or null when the payload is malformed, was encrypted
    /// with another key or for another purpose, or was altered in transit.</summary>
    public static string? TryDecrypt(string payload, byte[] key, string purpose)
    {
        var bytes = TryDecodeBase64(payload);
        if (bytes is null || bytes.Length < NonceSizeBytes + TagSizeBytes)
        {
            return null;
        }

        var ciphertextLength = bytes.Length - NonceSizeBytes - TagSizeBytes;
        var plaintext = new byte[ciphertextLength];

        try
        {
            using var aesGcm = new AesGcm(key, TagSizeBytes);
            aesGcm.Decrypt(
                bytes.AsSpan(0, NonceSizeBytes),
                bytes.AsSpan(NonceSizeBytes, ciphertextLength),
                bytes.AsSpan(NonceSizeBytes + ciphertextLength, TagSizeBytes),
                plaintext,
                AssociatedData(purpose));
        }
        catch (CryptographicException)
        {
            return null;
        }

        return Encoding.UTF8.GetString(plaintext);
    }

    private static byte[] AssociatedData(string purpose) => Encoding.UTF8.GetBytes(AssociatedDataPrefix + purpose);

    private static byte[]? TryDecodeBase64(string value)
    {
        var normalized = value.Trim().Replace('-', '+').Replace('_', '/');
        normalized = normalized.PadRight(normalized.Length + (4 - normalized.Length % 4) % 4, '=');

        try
        {
            return Convert.FromBase64String(normalized);
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
