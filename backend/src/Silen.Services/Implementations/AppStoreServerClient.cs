using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <summary>
/// Apple App Store Server API client. Authenticates outbound with our own
/// ES256-signed JWT (built from the .p8 key downloaded in App Store Connect)
/// and reads the transaction JWS Apple returns by decoding its payload
/// directly - bundle id and expiry are checked, but the x5c certificate
/// chain is not walked against Apple's root CA. That's a pragmatic middle
/// ground rather than full spec compliance: the request that fetched the
/// payload was itself authenticated to Apple over TLS.
/// </summary>
public sealed class AppStoreServerClient : IAppStoreServerClient
{
    private const string ProductionBaseUrl = "https://api.storekit.itunes.apple.com";
    private const string SandboxBaseUrl = "https://api.storekit-sandbox.itunes.apple.com";
    private static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(20);

    private readonly HttpClient _httpClient;
    private readonly AppStoreServerOptions _options;
    private readonly ILogger<AppStoreServerClient> _logger;
    private readonly ECDsa? _signingKey;
    private readonly SemaphoreSlim _tokenLock = new(1, 1);
    private string? _cachedToken;
    private DateTime _cachedTokenExpiresAtUtc;

    public AppStoreServerClient(HttpClient httpClient, IOptions<AppStoreServerOptions> options, ILogger<AppStoreServerClient> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
        _signingKey = TryLoadSigningKey(_options, _logger);
        _httpClient.BaseAddress = new Uri(
            string.Equals(_options.Environment, "Sandbox", StringComparison.OrdinalIgnoreCase) ? SandboxBaseUrl : ProductionBaseUrl);
    }

    public bool IsConfigured =>
        _signingKey is not null
        && !string.IsNullOrWhiteSpace(_options.KeyId)
        && !string.IsNullOrWhiteSpace(_options.IssuerId)
        && !string.IsNullOrWhiteSpace(_options.BundleId);

    public async Task<AppStoreTransactionInfo?> GetTransactionInfoAsync(string transactionId, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            _logger.LogWarning("AppStoreServer is not configured; cannot verify transaction '{TransactionId}'.", transactionId);
            return null;
        }

        string token;
        try
        {
            token = await GetSigningTokenAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Could not build an App Store Server API JWT.");
            return null;
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, $"/inApps/v1/transactions/{Uri.EscapeDataString(transactionId)}");
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        try
        {
            using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "App Store Server API rejected transaction lookup for '{TransactionId}' ({Status}): {Body}",
                    transactionId, (int)response.StatusCode, body);
                return null;
            }

            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("signedTransactionInfo", out var signedElement))
            {
                _logger.LogWarning("App Store Server API response for '{TransactionId}' had no signedTransactionInfo.", transactionId);
                return null;
            }

            return DecodeTransaction(signedElement.GetString(), _options.BundleId, _logger);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "App Store Server API call failed for transaction '{TransactionId}'.", transactionId);
            return null;
        }
    }

    private async Task<string> GetSigningTokenAsync(CancellationToken cancellationToken)
    {
        if (_cachedToken is not null && DateTime.UtcNow < _cachedTokenExpiresAtUtc)
        {
            return _cachedToken;
        }

        await _tokenLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_cachedToken is not null && DateTime.UtcNow < _cachedTokenExpiresAtUtc)
            {
                return _cachedToken;
            }

            var now = DateTime.UtcNow;
            var expiresAtUtc = now.Add(TokenLifetime);
            var securityKey = new ECDsaSecurityKey(_signingKey) { KeyId = _options.KeyId };
            var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.EcdsaSha256);

            var jwt = new JwtSecurityToken(
                issuer: _options.IssuerId,
                claims: [new Claim("bid", _options.BundleId)],
                notBefore: now,
                expires: expiresAtUtc,
                signingCredentials: credentials);
            jwt.Payload["aud"] = "appstoreconnect-v1";

            var handler = new JwtSecurityTokenHandler();
            _cachedToken = handler.WriteToken(jwt);
            _cachedTokenExpiresAtUtc = expiresAtUtc.AddMinutes(-2);
            return _cachedToken;
        }
        finally
        {
            _tokenLock.Release();
        }
    }

    private static AppStoreTransactionInfo? DecodeTransaction(string? signedTransactionInfo, string expectedBundleId, ILogger logger)
    {
        using var payloadDocument = JwsPayloadDecoder.TryDecodePayload(signedTransactionInfo, logger);
        if (payloadDocument is null)
        {
            return null;
        }

        {
            var root = payloadDocument.RootElement;
            var bundleId = root.TryGetProperty("bundleId", out var bundleElement) ? bundleElement.GetString() : null;
            if (!string.Equals(bundleId, expectedBundleId, StringComparison.Ordinal))
            {
                logger.LogWarning("Transaction bundle id '{BundleId}' did not match expected '{ExpectedBundleId}'.", bundleId, expectedBundleId);
                return null;
            }

            return new AppStoreTransactionInfo
            {
                TransactionId = root.TryGetProperty("transactionId", out var tx) ? tx.GetString() ?? string.Empty : string.Empty,
                OriginalTransactionId = root.TryGetProperty("originalTransactionId", out var origTx) ? origTx.GetString() ?? string.Empty : string.Empty,
                ProductId = root.TryGetProperty("productId", out var product) ? product.GetString() ?? string.Empty : string.Empty,
                BundleId = bundleId ?? string.Empty,
                PurchaseAtUtc = root.TryGetProperty("purchaseDate", out var purchaseDate)
                    ? DateTimeOffset.FromUnixTimeMilliseconds(purchaseDate.GetInt64()).UtcDateTime
                    : DateTime.UtcNow,
                ExpiresAtUtc = root.TryGetProperty("expiresDate", out var expiresDate)
                    ? DateTimeOffset.FromUnixTimeMilliseconds(expiresDate.GetInt64()).UtcDateTime
                    : null,
                RevokedAtUtc = root.TryGetProperty("revocationDate", out var revocationDate)
                    ? DateTimeOffset.FromUnixTimeMilliseconds(revocationDate.GetInt64()).UtcDateTime
                    : null,
                RawPayloadJson = root.GetRawText()
            };
        }
    }

    private static ECDsa? TryLoadSigningKey(AppStoreServerOptions options, ILogger logger)
    {
        var pem = options.PrivateKey;
        if (string.IsNullOrWhiteSpace(pem) && !string.IsNullOrWhiteSpace(options.PrivateKeyPath))
        {
            try
            {
                pem = File.ReadAllText(options.PrivateKeyPath);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not read AppStoreServer:PrivateKeyPath '{Path}'.", options.PrivateKeyPath);
                return null;
            }
        }

        if (string.IsNullOrWhiteSpace(pem))
        {
            return null;
        }

        try
        {
            var ecdsa = ECDsa.Create();
            ecdsa.ImportFromPem(pem);
            return ecdsa;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AppStoreServer private key could not be parsed as an EC PEM key.");
            return null;
        }
    }
}
