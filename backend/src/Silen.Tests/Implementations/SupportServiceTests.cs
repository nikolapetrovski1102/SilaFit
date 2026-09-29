using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SupportServiceTests
{
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly SupportService sut;

    public SupportServiceTests()
    {
        sut = new SupportService(emailSender.Object, Options.Create(new SupportOptions { InboxAddress = "support@sila.fitness" }));
    }

    private static SupportContactRequest ValidRequest() => new()
    {
        Name = "Alex",
        Email = " alex@example.com ",
        Topic = "bug",
        Message = "The timer <b>froze</b>\nafter my third set."
    };

    [Fact]
    public async Task ContactAsync_MailsTheInboxWithTheVisitorAsReplyTo()
    {
        string? subject = null, html = null;
        emailSender.Setup(s => s.SendWithReplyToAsync(
                "support@sila.fitness", It.IsAny<string>(), It.IsAny<string>(), "alex@example.com", It.IsAny<CancellationToken>()))
            .Callback<string, string, string, string, CancellationToken>((_, s, h, _, _) => { subject = s; html = h; })
            .Returns(Task.CompletedTask);

        var result = await sut.ContactAsync(ValidRequest());

        Assert.True(result.IsSuccess);
        Assert.Equal("[Support] Bug report - Alex", subject);
        Assert.Contains("&lt;b&gt;froze&lt;/b&gt;<br>after", html);
        Assert.DoesNotContain("<b>froze", html);
    }

    [Fact]
    public async Task ContactAsync_FilledHoneypot_SucceedsWithoutSending()
    {
        var request = ValidRequest();
        request.Website = "http://spam.example";

        var result = await sut.ContactAsync(request);

        Assert.True(result.IsSuccess);
        emailSender.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ContactAsync_UnknownTopic_IsRejected()
    {
        var request = ValidRequest();
        request.Topic = "pizza";

        var result = await sut.ContactAsync(request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ContactAsync_SmtpFailure_Returns503WithFallbackAddress()
    {
        emailSender.Setup(s => s.SendWithReplyToAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("smtp down"));

        var result = await sut.ContactAsync(ValidRequest());

        Assert.False(result.IsSuccess);
        Assert.Equal(503, result.StatusCode);
        Assert.Contains("support@sila.fitness", result.UserMessage);
    }

    [Fact]
    public void Template_StripsLineBreaksFromTheSubject()
    {
        var (subject, _) = SupportContactEmailTemplate.Build("Eve\r\nBcc: x@y.z", "eve@example.com", "Bug report", "Hello there");

        Assert.DoesNotContain("\n", subject);
        Assert.DoesNotContain("\r", subject);
    }
}
