using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Options;
using ValidationException = Silen.Common.Exceptions.ValidationException;
using UnauthorizedAppException = Silen.Common.Exceptions.UnauthorizedAppException;

namespace Silen.Services.Helpers;

/// <summary>
/// Both directions of the partner payload encryption: turns an encrypted request into a
/// validated payload (decrypt, parse, check IssuedAtUtc is fresh) and seals the response. The messages are written for the
/// partner's developers - no end user ever sees them.
/// </summary>
public static class PartnerPayloadCodec
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private static readonly HashSet<string> Providers = new(StringComparer.OrdinalIgnoreCase) { "Apple", "Google", "Email" };

    private static readonly EmailAddressAttribute EmailValidator = new();

    public static T Decrypt<T>(string payload, PartnerOptions options, string purpose)
    {
        var plaintext = PartnerPayloadCipher.TryDecrypt(payload, ReadKey(options), purpose)
            ?? throw new UnauthorizedAppException(
                $"Partner {purpose} payload failed to decrypt.",
                "The payload could not be decrypted. Check the key, the nonce|ciphertext|tag layout and the associated data.");

        try
        {
            return JsonSerializer.Deserialize<T>(plaintext, JsonOptions)
                ?? throw new ValidationException($"Partner {purpose} payload decrypted to JSON null.", "The payload must be a JSON object.");
        }
        catch (JsonException ex)
        {
            throw new ValidationException($"Partner {purpose} payload is not valid JSON: {ex.Message}", "The payload is not valid JSON.");
        }
    }

    public static PartnerEncryptedResponse Seal<T>(T value, PartnerOptions options, string purpose) => new()
    {
        Payload = PartnerPayloadCipher.Encrypt(JsonSerializer.Serialize(value, JsonOptions), ReadKey(options), purpose)
    };

    /// <summary>The payload's IssuedAtUtc as a UTC DateTime at millisecond precision (what the
    /// database stores), once it is known to be within the allowed clock window.</summary>
    public static DateTime RequireFreshIssuedAt(DateTimeOffset? issuedAt, PartnerOptions options, DateTime nowUtc)
    {
        if (issuedAt is null)
        {
            throw new ValidationException("Partner payload has no issuedAtUtc.", "issuedAtUtc is required.");
        }

        var issuedAtUtc = issuedAt.Value.UtcDateTime;
        if (Math.Abs((nowUtc - issuedAtUtc).TotalSeconds) > options.MaxPayloadAgeSeconds)
        {
            throw new UnauthorizedAppException(
                $"Partner payload issuedAtUtc {issuedAtUtc:O} is outside the {options.MaxPayloadAgeSeconds}s window.",
                "The payload has expired. Build a fresh payload for every request and check the server clock.");
        }

        return new DateTime(issuedAtUtc.Ticks - issuedAtUtc.Ticks % TimeSpan.TicksPerMillisecond, DateTimeKind.Utc);
    }

    public static string RequirePartnerUserId(string? partnerUserId)
    {
        var trimmed = partnerUserId?.Trim();
        if (string.IsNullOrEmpty(trimmed) || trimmed.Length > 100)
        {
            throw new ValidationException("Partner payload has a missing or over-long partnerUserId.", "partnerUserId is required (at most 100 characters).");
        }

        return trimmed;
    }

    /// <summary>Validated, trimmed (email, display name, provider) of a provision payload. The
    /// provider comes back in its canonical casing, as the database's check constraint expects.</summary>
    public static (string Email, string? DisplayName, string Provider) RequireLeadDetails(PartnerProvisionPayload payload)
    {
        var email = payload.Email?.Trim();
        if (string.IsNullOrEmpty(email) || email.Length > 256 || !EmailValidator.IsValid(email))
        {
            throw new ValidationException("Partner provision payload has a missing or invalid email.", "email must be a valid email address.");
        }

        var displayName = string.IsNullOrWhiteSpace(payload.DisplayName) ? null : payload.DisplayName.Trim();
        if (displayName is { Length: > 100 })
        {
            displayName = displayName[..100];
        }

        if (payload.Provider is null || !Providers.TryGetValue(payload.Provider.Trim(), out var provider))
        {
            throw new ValidationException(
                $"Partner provision payload has unknown provider '{payload.Provider}'.", "provider must be Apple, Google or Email.");
        }

        return (email, displayName, provider);
    }

    private static byte[] ReadKey(PartnerOptions options)
    {
        try
        {
            var key = Convert.FromBase64String(options.PayloadKeyBase64);
            if (key.Length == 32)
            {
                return key;
            }
        }
        catch (FormatException)
        {
        }

        throw new InvalidOperationException("Partner:PayloadKeyBase64 must be a base64-encoded 32-byte key.");
    }
}
