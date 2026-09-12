using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Silen.Common.Helpers;

/// <summary>
/// AES-256-GCM field-level encryption for sensitive columns (bodyweight,
/// height/age/gender/goal, meal titles/macros, nutrition targets) - see
/// Silen.Common/Options/EncryptionOptions.cs for where the master key comes
/// from. Mirrors the static-helper style of PasswordHasher, but this is
/// reversible encryption (not a one-way hash) since the plaintext value
/// needs to be shown back to the owning user.
///
/// Layout of an encrypted value, all in one byte[] so it fits a single
/// VARBINARY column: [12-byte nonce][ciphertext][16-byte tag].
/// </summary>
public static class FieldCipher
{
    private const int NonceSizeBytes = 12;
    private const int TagSizeBytes = 16;
    public const int KeySizeBytes = 32;

    public static byte[] EncryptString(string plaintext, byte[] key)
    {
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        return Encrypt(plaintextBytes, key);
    }

    public static string DecryptString(byte[] ciphertext, byte[] key) =>
        Encoding.UTF8.GetString(Decrypt(ciphertext, key));

    public static byte[] EncryptDecimal(decimal value, byte[] key) =>
        EncryptString(value.ToString(CultureInfo.InvariantCulture), key);

    public static decimal DecryptDecimal(byte[] ciphertext, byte[] key) =>
        decimal.Parse(DecryptString(ciphertext, key), CultureInfo.InvariantCulture);

    public static byte[] EncryptInt(int value, byte[] key) =>
        EncryptString(value.ToString(CultureInfo.InvariantCulture), key);

    public static int DecryptInt(byte[] ciphertext, byte[] key) =>
        int.Parse(DecryptString(ciphertext, key), CultureInfo.InvariantCulture);

    private static byte[] Encrypt(byte[] plaintextBytes, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(NonceSizeBytes);
        var ciphertextBytes = new byte[plaintextBytes.Length];
        var tag = new byte[TagSizeBytes];

        using (var aesGcm = new AesGcm(key, TagSizeBytes))
        {
            aesGcm.Encrypt(nonce, plaintextBytes, ciphertextBytes, tag);
        }

        var result = new byte[NonceSizeBytes + ciphertextBytes.Length + TagSizeBytes];
        Buffer.BlockCopy(nonce, 0, result, 0, NonceSizeBytes);
        Buffer.BlockCopy(ciphertextBytes, 0, result, NonceSizeBytes, ciphertextBytes.Length);
        Buffer.BlockCopy(tag, 0, result, NonceSizeBytes + ciphertextBytes.Length, TagSizeBytes);
        return result;
    }

    private static byte[] Decrypt(byte[] value, byte[] key)
    {
        var ciphertextLength = value.Length - NonceSizeBytes - TagSizeBytes;
        if (ciphertextLength < 0)
        {
            throw new CryptographicException("Encrypted value is shorter than the nonce+tag overhead.");
        }

        var nonce = value.AsSpan(0, NonceSizeBytes);
        var ciphertextBytes = value.AsSpan(NonceSizeBytes, ciphertextLength);
        var tag = value.AsSpan(NonceSizeBytes + ciphertextLength, TagSizeBytes);

        var plaintextBytes = new byte[ciphertextLength];
        using (var aesGcm = new AesGcm(key, TagSizeBytes))
        {
            aesGcm.Decrypt(nonce, ciphertextBytes, tag, plaintextBytes);
        }

        return plaintextBytes;
    }
}
