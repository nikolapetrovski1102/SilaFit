using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class PasswordHasherTests
{
    [Fact]
    public void Hash_ProducesExpectedSaltAndHashSizes()
    {
        var (hash, salt) = PasswordHasher.Hash("correct horse battery staple");

        Assert.Equal(32, hash.Length);
        Assert.Equal(16, salt.Length);
    }

    [Fact]
    public void Hash_IsSalted_SoTwoHashesOfTheSamePasswordDiffer()
    {
        var (hash1, salt1) = PasswordHasher.Hash("same-password");
        var (hash2, salt2) = PasswordHasher.Hash("same-password");

        Assert.NotEqual(salt1, salt2);
        Assert.NotEqual(hash1, hash2);
    }

    [Fact]
    public void Verify_CorrectPassword_ReturnsTrue()
    {
        var (hash, salt) = PasswordHasher.Hash("my-secret-password");

        Assert.True(PasswordHasher.Verify("my-secret-password", hash, salt));
    }

    [Fact]
    public void Verify_WrongPassword_ReturnsFalse()
    {
        var (hash, salt) = PasswordHasher.Hash("my-secret-password");

        Assert.False(PasswordHasher.Verify("not-the-password", hash, salt));
    }

    [Fact]
    public void Verify_HashFromADifferentPassword_ReturnsFalse()
    {
        var (_, salt) = PasswordHasher.Hash("password-a");
        var (unrelatedHash, _) = PasswordHasher.Hash("password-b");

        Assert.False(PasswordHasher.Verify("password-a", unrelatedHash, salt));
    }
}
