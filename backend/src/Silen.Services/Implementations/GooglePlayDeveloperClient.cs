using System.Text;
using System.Text.Json;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <summary>
/// Play Developer API client for verifying/acknowledging subscription
/// purchases. Reuses the same <see cref="ServiceAccountCredential"/> pattern
/// as <see cref="FcmPushNotificationSender"/>, scoped to androidpublisher
/// instead of firebase.messaging.
/// </summary>
public sealed class GooglePlayDeveloperClient : IGooglePlayDeveloperClient
{
    private const string AndroidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
    private const string BaseUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3";

    private readonly HttpClient _httpClient;
    private readonly GooglePlayOptions _options;
    private readonly ILogger<GooglePlayDeveloperClient> _logger;
    private readonly GoogleCredentialConfig? _config;
    private readonly SemaphoreSlim _credentialLock = new(1, 1);
    private ServiceAccountCredential? _credential;

    public GooglePlayDeveloperClient(HttpClient httpClient, IOptions<GooglePlayOptions> options, ILogger<GooglePlayDeveloperClient> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
        _config = TryLoadConfig(_options, _logger);
    }

    public bool IsConfigured => _config is not null && !string.IsNullOrWhiteSpace(_options.PackageName);

    public async Task<GooglePlaySubscriptionInfo?> GetSubscriptionAsync(string purchaseToken, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            _logger.LogWarning("GooglePlay is not configured; cannot verify a purchase token.");
            return null;
        }

        var url = $"{BaseUrl}/applications/{Uri.EscapeDataString(_options.PackageName)}/purchases/subscriptionsv2/tokens/{Uri.EscapeDataString(purchaseToken)}";

        try
        {
            var body = await SendAuthenticatedAsync(HttpMethod.Get, url, null, cancellationToken).ConfigureAwait(false);
            if (body is null)
            {
                return null;
            }

            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;

            var subscriptionState = root.TryGetProperty("subscriptionState", out var stateElement) ? stateElement.GetString() ?? string.Empty : string.Empty;
            var latestOrderId = root.TryGetProperty("latestOrderId", out var orderElement) ? orderElement.GetString() : null;
            var acknowledged = root.TryGetProperty("acknowledgementState", out var ackElement)
                && string.Equals(ackElement.GetString(), "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED", StringComparison.Ordinal);

            string productId = string.Empty;
            DateTime? expiresAtUtc = null;
            var autoRenewing = false;
            if (root.TryGetProperty("lineItems", out var lineItems) && lineItems.ValueKind == JsonValueKind.Array && lineItems.GetArrayLength() > 0)
            {
                var lineItem = lineItems[0];
                productId = lineItem.TryGetProperty("productId", out var productElement) ? productElement.GetString() ?? string.Empty : string.Empty;
                if (lineItem.TryGetProperty("expiryTime", out var expiryElement) && DateTime.TryParse(expiryElement.GetString(), out var expiry))
                {
                    expiresAtUtc = expiry.ToUniversalTime();
                }

                if (lineItem.TryGetProperty("autoRenewingPlan", out var autoRenewElement)
                    && autoRenewElement.TryGetProperty("autoRenewEnabled", out var autoRenewEnabledElement))
                {
                    autoRenewing = autoRenewEnabledElement.GetBoolean();
                }
            }

            return new GooglePlaySubscriptionInfo
            {
                ProductId = productId,
                LatestOrderId = latestOrderId,
                ExpiresAtUtc = expiresAtUtc,
                AutoRenewing = autoRenewing,
                SubscriptionState = subscriptionState,
                Acknowledged = acknowledged,
                RawPayloadJson = root.GetRawText()
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Play Developer API subscription lookup failed.");
            return null;
        }
    }

    public async Task<bool> AcknowledgeAsync(string purchaseToken, string productId, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            return false;
        }

        var url = $"{BaseUrl}/applications/{Uri.EscapeDataString(_options.PackageName)}/purchases/subscriptions/{Uri.EscapeDataString(productId)}/tokens/{Uri.EscapeDataString(purchaseToken)}:acknowledge";

        try
        {
            var body = await SendAuthenticatedAsync(HttpMethod.Post, url, "{}", cancellationToken).ConfigureAwait(false);
            return body is not null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Play Developer API acknowledge failed for product '{ProductId}'.", productId);
            return false;
        }
    }

    private async Task<string?> SendAuthenticatedAsync(HttpMethod method, string url, string? jsonBody, CancellationToken cancellationToken)
    {
        var accessToken = await GetAccessTokenAsync(cancellationToken).ConfigureAwait(false);

        using var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
        if (jsonBody is not null)
        {
            request.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
        }

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            _logger.LogWarning("Play Developer API call to '{Url}' failed ({Status}): {Body}", url, (int)response.StatusCode, body);
            return null;
        }

        return body;
    }

    private async Task<string> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        if (_credential is null)
        {
            await _credentialLock.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                if (_credential is null)
                {
                    var initializer = new ServiceAccountCredential.Initializer(_config!.ClientEmail)
                    {
                        Scopes = [AndroidPublisherScope],
                        KeyId = _config.PrivateKeyId
                    };
                    _credential = new ServiceAccountCredential(initializer.FromPrivateKey(_config.PrivateKey));
                }
            }
            finally
            {
                _credentialLock.Release();
            }
        }

        return await _credential.GetAccessTokenForRequestAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    private static GoogleCredentialConfig? TryLoadConfig(GooglePlayOptions options, ILogger logger)
    {
        var json = options.ServiceAccountJson;
        if (string.IsNullOrWhiteSpace(json) && !string.IsNullOrWhiteSpace(options.ServiceAccountJsonPath))
        {
            try
            {
                json = File.ReadAllText(options.ServiceAccountJsonPath);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not read GooglePlay:ServiceAccountJsonPath '{Path}'.", options.ServiceAccountJsonPath);
                return null;
            }
        }

        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var clientEmail = root.TryGetProperty("client_email", out var email) ? email.GetString() : null;
            var privateKey = root.TryGetProperty("private_key", out var key) ? key.GetString() : null;
            var privateKeyId = root.TryGetProperty("private_key_id", out var keyId) ? keyId.GetString() : null;

            if (string.IsNullOrWhiteSpace(clientEmail) || string.IsNullOrWhiteSpace(privateKey))
            {
                logger.LogWarning("GooglePlay service account JSON is missing client_email or private_key.");
                return null;
            }

            return new GoogleCredentialConfig(clientEmail!, privateKey!, privateKeyId);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "GooglePlay service account JSON could not be parsed.");
            return null;
        }
    }

    private sealed record GoogleCredentialConfig(string ClientEmail, string PrivateKey, string? PrivateKeyId);
}
