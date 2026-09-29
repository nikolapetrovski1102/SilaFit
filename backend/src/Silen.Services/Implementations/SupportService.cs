using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISupportService"/>
public sealed class SupportService(IEmailSender emailSender, IOptions<SupportOptions> options) : ISupportService
{
    /// <summary>The topics the support form offers, keyed by the value it posts.</summary>
    public static readonly IReadOnlyDictionary<string, string> Topics = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["account"] = "Account & sign-in",
        ["training"] = "Training & splits",
        ["nutrition"] = "Nutrition & meal plans",
        ["subscription"] = "Subscription & billing",
        ["bug"] = "Bug report",
        ["other"] = "Something else"
    };

    public Task<ServiceResult<bool>> ContactAsync(SupportContactRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // A filled honeypot is a bot. Report success so it has nothing to learn from.
            if (!string.IsNullOrWhiteSpace(request.Website))
            {
                return true;
            }

            if (!Topics.TryGetValue(request.Topic, out var topicLabel))
            {
                throw new ValidationException($"Unknown support topic '{request.Topic}'.", "Please choose a topic.");
            }

            var name = request.Name.Trim();
            var email = request.Email.Trim();
            var (subject, html) = SupportContactEmailTemplate.Build(name, email, topicLabel, request.Message.Trim());

            try
            {
                await emailSender.SendWithReplyToAsync(options.Value.InboxAddress, subject, html, email, cancellationToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                throw new SupportUnavailableException(ex);
            }

            return true;
        });

    private sealed class SupportUnavailableException(Exception inner) : AppException(
        503,
        "We couldn't send your message right now. Please email support@sila.fitness directly.",
        $"Support contact email failed: {inner}");
}
