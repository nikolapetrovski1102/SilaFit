using System.Security.Cryptography;
using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class PartnerPayloadCipherTests
{
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);

    [Fact]
    public void Encrypt_ThenTryDecrypt_RoundTrips()
    {
        const string plaintext = "{\"partnerUserId\":\"lead-1\",\"email\":\"lead@example.com\"}";

        var payload = PartnerPayloadCipher.Encrypt(plaintext, key, PartnerPayloadCipher.ProvisionPurpose);

        Assert.Equal(plaintext, PartnerPayloadCipher.TryDecrypt(payload, key, PartnerPayloadCipher.ProvisionPurpose));
    }

    [Fact]
    public void Encrypt_SamePlaintextTwice_UsesFreshNonce()
    {
        var first = PartnerPayloadCipher.Encrypt("same", key, PartnerPayloadCipher.ProvisionPurpose);
        var second = PartnerPayloadCipher.Encrypt("same", key, PartnerPayloadCipher.ProvisionPurpose);

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void TryDecrypt_StandardBase64_IsAccepted()
    {
        var payload = PartnerPayloadCipher.Encrypt("hello", key, PartnerPayloadCipher.CancelPurpose);
        var standard = payload.Replace('-', '+').Replace('_', '/');
        standard = standard.PadRight(standard.Length + (4 - standard.Length % 4) % 4, '=');

        Assert.Equal("hello", PartnerPayloadCipher.TryDecrypt(standard, key, PartnerPayloadCipher.CancelPurpose));
    }

    [Fact]
    public void TryDecrypt_OtherPurpose_ReturnsNull()
    {
        // A provision payload replayed against the cancel endpoint must not decrypt.
        var payload = PartnerPayloadCipher.Encrypt("{}", key, PartnerPayloadCipher.ProvisionPurpose);

        Assert.Null(PartnerPayloadCipher.TryDecrypt(payload, key, PartnerPayloadCipher.CancelPurpose));
    }

    [Fact]
    public void TryDecrypt_WrongKey_ReturnsNull()
    {
        var payload = PartnerPayloadCipher.Encrypt("{}", key, PartnerPayloadCipher.ProvisionPurpose);

        Assert.Null(PartnerPayloadCipher.TryDecrypt(payload, RandomNumberGenerator.GetBytes(32), PartnerPayloadCipher.ProvisionPurpose));
    }

    [Fact]
    public void TryDecrypt_TamperedCiphertext_ReturnsNull()
    {
        var payload = PartnerPayloadCipher.Encrypt("{\"a\":1}", key, PartnerPayloadCipher.ProvisionPurpose);
        var chars = payload.ToCharArray();
        chars[20] = chars[20] == 'A' ? 'B' : 'A';

        Assert.Null(PartnerPayloadCipher.TryDecrypt(new string(chars), key, PartnerPayloadCipher.ProvisionPurpose));
    }

    [Theory]
    [InlineData("")]
    [InlineData("not base64 at all!")]
    [InlineData("AAAA")]
    public void TryDecrypt_Garbage_ReturnsNull(string payload)
    {
        Assert.Null(PartnerPayloadCipher.TryDecrypt(payload, key, PartnerPayloadCipher.ProvisionPurpose));
    }
}
