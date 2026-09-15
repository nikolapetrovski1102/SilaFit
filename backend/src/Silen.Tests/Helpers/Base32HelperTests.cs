using System.Text;
using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class Base32HelperTests
{
    // RFC 4648 §10 test vectors, with the standard '=' padding stripped since
    // Base32Helper.Encode deliberately omits it.
    [Theory]
    [InlineData("", "")]
    [InlineData("f", "MY")]
    [InlineData("fo", "MZXQ")]
    [InlineData("foo", "MZXW6")]
    [InlineData("foob", "MZXW6YQ")]
    [InlineData("fooba", "MZXW6YTB")]
    [InlineData("foobar", "MZXW6YTBOI")]
    public void Encode_MatchesRfc4648TestVectors(string input, string expected)
    {
        var encoded = Base32Helper.Encode(Encoding.ASCII.GetBytes(input));

        Assert.Equal(expected, encoded);
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("MY", "f")]
    [InlineData("MZXQ", "fo")]
    [InlineData("MZXW6", "foo")]
    [InlineData("MZXW6YQ", "foob")]
    [InlineData("MZXW6YTB", "fooba")]
    [InlineData("MZXW6YTBOI", "foobar")]
    public void Decode_MatchesRfc4648TestVectors(string encoded, string expected)
    {
        var decoded = Base32Helper.Decode(encoded);

        Assert.Equal(expected, Encoding.ASCII.GetString(decoded));
    }

    [Fact]
    public void Decode_IsCaseInsensitive_AndIgnoresPaddingSpacesAndDashes()
    {
        var canonical = Base32Helper.Decode("MZXW6YTBOI");
        var messy = Base32Helper.Decode("mzxw6-ytbo i====");

        Assert.Equal(canonical, messy);
    }

    [Fact]
    public void Decode_InvalidCharacter_ThrowsFormatException()
    {
        Assert.Throws<FormatException>(() => Base32Helper.Decode("MZXW6YTB01")); // '0' and '1' aren't in the alphabet
    }

    [Fact]
    public void RoundTrip_RandomBytes_RecoversOriginalValue()
    {
        var original = System.Security.Cryptography.RandomNumberGenerator.GetBytes(20);

        var roundTripped = Base32Helper.Decode(Base32Helper.Encode(original));

        Assert.Equal(original, roundTripped);
    }
}
