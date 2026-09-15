using System.Security.Cryptography;
using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class AdminTotpSecretCipherTests
{
    private static byte[] MasterKey() => RandomNumberGenerator.GetBytes(FieldCipher.KeySizeBytes);

    [Fact]
    public void Encrypt_Decrypt_RoundTripsTheBase32Secret()
    {
        var key = MasterKey();
        var secret = TotpHelper.GenerateSecret();

        var ciphertext = AdminTotpSecretCipher.Encrypt(secret, key);

        Assert.Equal(secret, AdminTotpSecretCipher.Decrypt(ciphertext, key));
    }

    [Fact]
    public void ParseMasterKey_ValidBase64_Returns32Bytes()
    {
        var key = MasterKey();
        var base64 = Convert.ToBase64String(key);

        var parsed = AdminTotpSecretCipher.ParseMasterKey(base64);

        Assert.Equal(key, parsed);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ParseMasterKey_MissingConfiguration_ThrowsWithASettingNameInTheMessage(string? blank)
    {
        var exception = Assert.Throws<InvalidOperationException>(() => AdminTotpSecretCipher.ParseMasterKey(blank!));
        Assert.Contains("Encryption:MasterKeyBase64", exception.Message);
    }

    [Fact]
    public void ParseMasterKey_InvalidBase64_ThrowsInvalidOperationException_NotFormatException()
    {
        Assert.Throws<InvalidOperationException>(() => AdminTotpSecretCipher.ParseMasterKey("not-valid-base64!!!"));
    }

    [Fact]
    public void ParseMasterKey_WrongDecodedLength_ThrowsWithTheExpectedAndActualLengths()
    {
        var sixteenByteKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));

        var exception = Assert.Throws<InvalidOperationException>(() => AdminTotpSecretCipher.ParseMasterKey(sixteenByteKey));
        Assert.Contains("32", exception.Message);
        Assert.Contains("16", exception.Message);
    }
}
