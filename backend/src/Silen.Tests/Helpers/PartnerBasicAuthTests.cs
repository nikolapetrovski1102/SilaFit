using System.Text;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Xunit;

namespace Silen.Tests.Helpers;

public class PartnerBasicAuthTests
{
    private static readonly PartnerOptions Options = new() { Username = "partner", Password = "s3cret:with:colons" };

    private static string Basic(string credentials) => "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(credentials));

    [Fact]
    public void IsAuthorized_CorrectCredentials_True()
    {
        // The password may itself contain ':' - only the first one separates the user.
        Assert.True(PartnerBasicAuth.IsAuthorized(Basic("partner:s3cret:with:colons"), Options));
    }

    [Fact]
    public void IsAuthorized_LowercaseScheme_True()
    {
        Assert.True(PartnerBasicAuth.IsAuthorized("basic " + Basic("partner:s3cret:with:colons")[6..], Options));
    }

    [Theory]
    [InlineData("partner:wrong")]
    [InlineData("other:s3cret:with:colons")]
    [InlineData("partner")]
    [InlineData(":")]
    public void IsAuthorized_WrongCredentials_False(string credentials)
    {
        Assert.False(PartnerBasicAuth.IsAuthorized(Basic(credentials), Options));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Bearer abc")]
    [InlineData("Basic !!!not-base64")]
    public void IsAuthorized_MalformedHeader_False(string? header)
    {
        Assert.False(PartnerBasicAuth.IsAuthorized(header, Options));
    }

    [Fact]
    public void IsAuthorized_CredentialsNotConfigured_RefusesEverything()
    {
        var unconfigured = new PartnerOptions();

        Assert.False(PartnerBasicAuth.IsAuthorized(Basic(":"), unconfigured));
    }
}
