using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <summary>
/// Firebase Cloud Messaging HTTP v1 transport. Authenticates with a service
/// account (access token cached by <see cref="ServiceAccountCredential"/>) and
/// posts one message per device token. Invalid/unregistered tokens are
/// reported back so the publisher can deactivate them.
/// </summary>
public sealed class FcmPushNotificationSender : IPushNotificationSender
{
    private const string FirebaseMessagingScope = "https://www.googleapis.com/auth/firebase.messaging";
    private const string HttpClientName = "fcm";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly PushNotificationOptions _options;
    private readonly ILogger<FcmPushNotificationSender> _logger;
    private readonly FcmConfig? _config;
    private readonly SemaphoreSlim _credentialLock = new(1, 1);
    private ServiceAccountCredential? _credential;

    public FcmPushNotificationSender(
        IHttpClientFactory httpClientFactory,
        IOptions<PushNotificationOptions> options,
        ILogger<FcmPushNotificationSender> logger)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
        _logger = logger;
        _config = TryLoadConfig(_options, _logger);
    }

    public bool IsConfigured => _config is not null;

    /// <summary>
    /// Cheap pre-flight for DI: whether an FCM sender is worth constructing at
    /// all. A full parse happens in the constructor; this only checks that push
    /// is on and some service account was supplied.
    /// </summary>
    public static bool CanConfigure(PushNotificationOptions options) =>
        options.Enabled
        && (!string.IsNullOrWhiteSpace(options.ServiceAccountJson)
            || !string.IsNullOrWhiteSpace(options.ServiceAccountJsonPath));

    public async Task<PushSendResult> SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default)
    {
        if (_config is null)
        {
            return PushSendResult.Failed("FCM is not configured.");
        }

        string accessToken;
        try
        {
            accessToken = await GetAccessTokenAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Could not obtain an FCM access token.");
            return PushSendResult.Failed($"FCM auth failed: {ex.Message}");
        }

        var endpoint = $"{_options.BaseUrl.TrimEnd('/')}/v1/projects/{_config.ProjectId}/messages:send";
        var payload = BuildPayload(message);
        var json = JsonSerializer.Serialize(payload, JsonOptions);

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        try
        {
            var client = _httpClientFactory.CreateClient(HttpClientName);
            using var response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

            if (response.IsSuccessStatusCode)
            {
                using var document = JsonDocument.Parse(body);
                var name = document.RootElement.TryGetProperty("name", out var nameElement)
                    ? nameElement.GetString()
                    : null;
                return PushSendResult.Sent(name);
            }

            var error = ExtractError(body);
            var tokenInvalid = IsTokenInvalid(body);
            _logger.LogWarning("FCM rejected a message ({Status}): {Error}", (int)response.StatusCode, error);
            return PushSendResult.Failed(error, tokenInvalid);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM send failed.");
            return PushSendResult.Failed(ex.Message);
        }
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
                        Scopes = [FirebaseMessagingScope],
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

    private object BuildPayload(PushNotificationMessage message)
    {
        var data = message.Data.ToDictionary(kv => kv.Key, kv => kv.Value);

        return new Dictionary<string, object?>
        {
            ["message"] = new Dictionary<string, object?>
            {
                ["token"] = message.Token,
                ["notification"] = new { title = message.Title, body = message.Body },
                ["data"] = data,
                ["android"] = new
                {
                    priority = "high",
                    ttl = $"{message.TtlSeconds ?? _options.DefaultTtlSeconds}s",
                    notification = new { channel_id = "silen_reminders", sound = "default" }
                },
                ["apns"] = new
                {
                    payload = new { aps = new { sound = "default", contentAvailable = true } }
                }
            }
        };
    }

    private static string ExtractError(string body)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.TryGetProperty("error", out var error))
            {
                var message = error.TryGetProperty("message", out var messageElement)
                    ? messageElement.GetString()
                    : null;
                var status = error.TryGetProperty("status", out var statusElement)
                    ? statusElement.GetString()
                    : null;
                return $"{(status ?? "ERROR")}: {message ?? "FCM send failed."}";
            }
        }
        catch (JsonException)
        {
            // Fall through to the raw body.
        }

        return body.Length > 500 ? body[..500] : body;
    }

    private static bool IsTokenInvalid(string body) =>
        body.Contains("UNREGISTERED", StringComparison.OrdinalIgnoreCase)
        || body.Contains("SENDER_ID_MISMATCH", StringComparison.OrdinalIgnoreCase)
        || body.Contains("INVALID_ARGUMENT", StringComparison.OrdinalIgnoreCase);

    private static FcmConfig? TryLoadConfig(PushNotificationOptions options, ILogger logger)
    {
        if (!options.Enabled)
        {
            return null;
        }

        var json = options.ServiceAccountJson;
        if (string.IsNullOrWhiteSpace(json) && !string.IsNullOrWhiteSpace(options.ServiceAccountJsonPath))
        {
            try
            {
                json = File.ReadAllText(options.ServiceAccountJsonPath);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not read Push:ServiceAccountJsonPath '{Path}'.", options.ServiceAccountJsonPath);
                return null;
            }
        }

        if (string.IsNullOrWhiteSpace(json))
        {
            logger.LogWarning("Push is enabled but no service account JSON was supplied; falling back to log-only sends.");
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var clientEmail = root.TryGetProperty("client_email", out var email) ? email.GetString() : null;
            var privateKey = root.TryGetProperty("private_key", out var key) ? key.GetString() : null;
            var projectId = !string.IsNullOrWhiteSpace(options.ProjectId)
                ? options.ProjectId
                : root.TryGetProperty("project_id", out var project) ? project.GetString() : null;
            var privateKeyId = root.TryGetProperty("private_key_id", out var keyId) ? keyId.GetString() : null;

            if (string.IsNullOrWhiteSpace(clientEmail) || string.IsNullOrWhiteSpace(privateKey) || string.IsNullOrWhiteSpace(projectId))
            {
                logger.LogWarning("Push service account JSON is missing client_email, private_key, or project_id.");
                return null;
            }

            return new FcmConfig(projectId!, clientEmail!, privateKey!, privateKeyId);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Push service account JSON could not be parsed.");
            return null;
        }
    }

    private sealed record FcmConfig(string ProjectId, string ClientEmail, string PrivateKey, string? PrivateKeyId);
}
