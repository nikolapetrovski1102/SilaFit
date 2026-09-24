using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <summary>
/// Talks to Apple's Sign in with Apple REST API (/auth/token, /auth/revoke),
/// authenticating with a client secret: a short-lived ES256 JWT signed with
/// the Sign in with Apple .p8 key from <see cref="AppleAuthOptions"/>.
/// </summary>
public sealed class AppleSignInRevoker : IAppleSignInRevoker
{
    private const string AppleBaseUrl = "https://appleid.apple.com";
    private static readonly TimeSpan ClientSecretLifetime = TimeSpan.FromMinutes(5);

    private readonly HttpClient _httpClient;
    private readonly AppleAuthOptions _options;
    private readonly IAccountProvider _accountProvider;
    private readonly ILogger<AppleSignInRevoker> _logger;
    private readonly ECDsa? _signingKey;

    public AppleSignInRevoker(
        HttpClient httpClient,
        IOptions<AppleAuthOptions> options,
        IAccountProvider accountProvider,
        ILogger<AppleSignInRevoker> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _accountProvider = accountProvider;
        _logger = logger;
        _signingKey = TryLoadSigningKey(_options, _logger);
    }

    // The native app's authorization codes are issued to its bundle id.
    private string? ClientId => _options.ClientIds.FirstOrDefault(id => !string.IsNullOrWhiteSpace(id));

    private bool IsConfigured =>
        _signingKey is not null
        && ClientId is not null
        && !string.IsNullOrWhiteSpace(_options.TeamId)
        && !string.IsNullOrWhiteSpace(_options.KeyId);

    public async Task StoreAuthorizationAsync(Guid userId, string authorizationCode, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            _logger.LogWarning("AppleAuth signing key is not configured; not storing a refresh token for user '{UserId}'.", userId);
            return;
        }

        try
        {
            using var response = await _httpClient.PostAsync(
                $"{AppleBaseUrl}/auth/token",
                new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["client_id"] = ClientId!,
                    ["client_secret"] = CreateClientSecret(),
                    ["code"] = authorizationCode,
                    ["grant_type"] = "authorization_code"
                }),
                cancellationToken).ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Apple rejected the authorization code for user '{UserId}' with {StatusCode}: {Body}",
                    userId, (int)response.StatusCode, await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
                return;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (!document.RootElement.TryGetProperty("refresh_token", out var refreshToken)
                || string.IsNullOrWhiteSpace(refreshToken.GetString()))
            {
                _logger.LogWarning("Apple's token response for user '{UserId}' had no refresh_token.", userId);
                return;
            }

            await _accountProvider.SetAppleRefreshTokenAsync(userId, refreshToken.GetString()!, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "Could not exchange the Apple authorization code for user '{UserId}'.", userId);
        }
    }

    public async Task RevokeAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        try
        {
            var refreshToken = await _accountProvider.GetAppleRefreshTokenAsync(userId, cancellationToken).ConfigureAwait(false);
            if (refreshToken is null)
            {
                return;
            }

            if (!IsConfigured)
            {
                _logger.LogWarning("AppleAuth signing key is not configured; cannot revoke the Apple token for user '{UserId}'.", userId);
                return;
            }

            using var response = await _httpClient.PostAsync(
                $"{AppleBaseUrl}/auth/revoke",
                new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["client_id"] = ClientId!,
                    ["client_secret"] = CreateClientSecret(),
                    ["token"] = refreshToken,
                    ["token_type_hint"] = "refresh_token"
                }),
                cancellationToken).ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Apple token revocation for user '{UserId}' failed with {StatusCode}: {Body}",
                    userId, (int)response.StatusCode, await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "Could not revoke the Apple token for user '{UserId}'.", userId);
        }
    }

    private string CreateClientSecret()
    {
        var now = DateTime.UtcNow;
        var securityKey = new ECDsaSecurityKey(_signingKey) { KeyId = _options.KeyId };
        var jwt = new JwtSecurityToken(
            issuer: _options.TeamId,
            audience: AppleBaseUrl,
            claims: [new Claim(JwtRegisteredClaimNames.Sub, ClientId!)],
            notBefore: now,
            expires: now.Add(ClientSecretLifetime),
            signingCredentials: new SigningCredentials(securityKey, SecurityAlgorithms.EcdsaSha256));
        jwt.Payload[JwtRegisteredClaimNames.Iat] = EpochTime.GetIntDate(now);
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }

    private static ECDsa? TryLoadSigningKey(AppleAuthOptions options, ILogger logger)
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
                logger.LogWarning(ex, "Could not read AppleAuth:PrivateKeyPath '{Path}'.", options.PrivateKeyPath);
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
            logger.LogWarning(ex, "AppleAuth private key could not be parsed as an EC PEM key.");
            return null;
        }
    }
}
