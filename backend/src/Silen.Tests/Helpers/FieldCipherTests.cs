using System.Security.Cryptography;
using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class FieldCipherTests
{
    private static byte[] Key() => RandomNumberGenerator.GetBytes(FieldCipher.KeySizeBytes);

    [Fact]
    public void EncryptString_DecryptString_RoundTrips()
    {
        var key = Key();

        var ciphertext = FieldCipher.EncryptString("sensitive value", key);

        Assert.Equal("sensitive value", FieldCipher.DecryptString(ciphertext, key));
    }

    [Fact]
    public void EncryptDecimal_DecryptDecimal_RoundTrips_RegardlessOfCulture()
    {
        var key = Key();

        var ciphertext = FieldCipher.EncryptDecimal(72.5m, key);

        Assert.Equal(72.5m, FieldCipher.DecryptDecimal(ciphertext, key));
    }

    [Fact]
    public void EncryptInt_DecryptInt_RoundTrips()
    {
        var key = Key();

        var ciphertext = FieldCipher.EncryptInt(-42, key);

        Assert.Equal(-42, FieldCipher.DecryptInt(ciphertext, key));
    }

    [Fact]
    public void Encrypt_UsesARandomNonce_SoRepeatedEncryptionsOfTheSameValueDiffer()
    {
        var key = Key();

        var first = FieldCipher.EncryptString("same plaintext", key);
        var second = FieldCipher.EncryptString("same plaintext", key);

        Assert.NotEqual(first, second);
        // Both must still decrypt correctly despite the differing ciphertext bytes.
        Assert.Equal("same plaintext", FieldCipher.DecryptString(first, key));
        Assert.Equal("same plaintext", FieldCipher.DecryptString(second, key));
    }

    [Fact]
    public void Decrypt_WithWrongKey_ThrowsRatherThanReturningGarbage()
    {
        var ciphertext = FieldCipher.EncryptString("secret", Key());

        Assert.ThrowsAny<CryptographicException>(() => FieldCipher.DecryptString(ciphertext, Key()));
    }

    [Fact]
    public void Decrypt_TamperedCiphertext_ThrowsInsteadOfSilentlyCorrupting()
    {
        var key = Key();
        var ciphertext = FieldCipher.EncryptString("secret", key);
        ciphertext[^1] ^= 0xFF; // flip a bit inside the GCM tag

        Assert.ThrowsAny<CryptographicException>(() => FieldCipher.DecryptString(ciphertext, key));
    }

    [Fact]
    public void Decrypt_TruncatedValue_ThrowsRatherThanIndexingOutOfRange()
    {
        var key = Key();
        var tooShort = new byte[10]; // shorter than nonce(12) + tag(16) overhead

        Assert.Throws<CryptographicException>(() => FieldCipher.DecryptString(tooShort, key));
    }
}
