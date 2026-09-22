using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Api.Controllers;

/// <summary>
/// Store-to-server subscription notifications (App Store Server Notifications V2,
/// Play Real-time Developer Notifications). Anonymous by necessity - neither
/// store carries our JWTs - so no [Authorize] is used, matching this codebase's
/// convention of anonymity-by-omission. Always acknowledges with 200, even when
/// a payload can't be processed, since both stores retry aggressively on a
/// non-2xx response and the periodic reconciliation job (Silen.Tools.SubscriptionSync)
/// is the safety net for anything missed here.
/// </summary>
[ApiController]
[Route("api/webhooks")]
[EnableRateLimiting(RateLimitPolicies.Webhooks)]
public sealed class SubscriptionWebhooksController(
    ISubscriptionReceiptService subscriptionReceiptService,
    IPlansProvider plansProvider,
    ILogger<SubscriptionWebhooksController> logger) : ControllerBase
{
    [HttpPost("apple")]
    public async Task<IActionResult> Apple([FromBody] AppleServerNotificationRequest notification, CancellationToken cancellationToken)
    {
        try
        {
            using var outerPayload = JwsPayloadDecoder.TryDecodePayload(notification.SignedPayload, logger);
            var signedTransactionInfo = outerPayload is not null
                && outerPayload.RootElement.TryGetProperty("data", out var data)
                && data.TryGetProperty("signedTransactionInfo", out var transactionInfoElement)
                ? transactionInfoElement.GetString()
                : null;

            using var transactionPayload = JwsPayloadDecoder.TryDecodePayload(signedTransactionInfo, logger);
            var transactionId = transactionPayload is not null
                && transactionPayload.RootElement.TryGetProperty("transactionId", out var transactionIdElement)
                ? transactionIdElement.GetString()
                : null;

            if (string.IsNullOrWhiteSpace(transactionId))
            {
                logger.LogWarning("Apple server notification did not contain a decodable transaction id.");
                return Ok();
            }

            await subscriptionReceiptService.ApplyStoreNotificationAsync("AppStore", transactionId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to process an Apple server notification.");
        }

        return Ok();
    }

    [HttpPost("google")]
    public async Task<IActionResult> Google([FromBody] PubSubPushEnvelope envelope, CancellationToken cancellationToken)
    {
        try
        {
            var purchaseToken = DecodePurchaseToken(envelope.Message?.Data);
            if (string.IsNullOrWhiteSpace(purchaseToken))
            {
                logger.LogWarning("Play Pub/Sub notification did not contain a decodable purchase token.");
                return Ok();
            }

            // Google's notification only says "something changed" for this token, not
            // which user/plan - the receipt row (written by the original verify call)
            // is what maps a purchase token back to a transaction we can re-verify.
            var receipt = await plansProvider.GetReceiptByPurchaseTokenAsync(purchaseToken, cancellationToken);
            if (receipt is null)
            {
                logger.LogInformation("Ignoring Play notification for an unknown purchase token.");
                return Ok();
            }

            await subscriptionReceiptService.ApplyStoreNotificationAsync("PlayStore", receipt.TransactionId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to process a Play Store server notification.");
        }

        return Ok();
    }

    private string? DecodePurchaseToken(string? base64Data)
    {
        if (string.IsNullOrWhiteSpace(base64Data))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(Convert.FromBase64String(base64Data));
            return document.RootElement.TryGetProperty("subscriptionNotification", out var subscriptionNotification)
                && subscriptionNotification.TryGetProperty("purchaseToken", out var tokenElement)
                ? tokenElement.GetString()
                : null;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not decode a Play Pub/Sub message body.");
            return null;
        }
    }
}
