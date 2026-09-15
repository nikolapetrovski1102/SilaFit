using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class VerificationEmailTemplateTests
{
    [Fact]
    public void Build_SubjectIsFixed()
    {
        var (subject, _) = VerificationEmailTemplate.Build("123456");

        Assert.Equal("Your SilaFit verification code", subject);
    }

    [Fact]
    public void Build_HtmlContainsTheCodeVerbatim()
    {
        var (_, html) = VerificationEmailTemplate.Build("482913");

        Assert.Contains("482913", html);
    }

    [Fact]
    public void Build_DifferentCodes_ProduceDifferentHtml()
    {
        var (_, htmlA) = VerificationEmailTemplate.Build("111111");
        var (_, htmlB) = VerificationEmailTemplate.Build("222222");

        Assert.NotEqual(htmlA, htmlB);
    }
}
