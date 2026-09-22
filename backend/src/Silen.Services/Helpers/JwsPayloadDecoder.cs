using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Silen.Services.Helpers;

/// <summary>
/// Decodes the base64url payload segment of a JWS without verifying its
/// signature. Used for Apple's App Store Server payloads (transaction info,
/// renewal info, server notifications) - the x5c certificate chain is
/// deliberately not walked against Apple's root CA (a pragmatic scope
/// decision), since every payload this decodes was itself fetched from Apple
/// over TLS via our own signed outbound JWT, or is a decoded value we only
/// use to look up an existing, already-verified receipt.
/// </summary>
public static class JwsPayloadDecoder
{
    public static JsonDocument? TryDecodePayload(string? jws, ILogger logger)
    {
        if (string.IsNullOrWhiteSpace(jws))
        {
            return null;
        }

        var segments = jws.Split('.');
        if (segments.Length != 3)
        {
            logger.LogWarning("Value was not a well-formed JWS.");
            return null;
        }

        try
        {
            return JsonDocument.Parse(Base64UrlDecode(segments[1]));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not decode JWS payload.");
            return null;
        }
    }

    private static byte[] Base64UrlDecode(string input)
    {
        var padded = input.Replace('-', '+').Replace('_', '/');
        switch (padded.Length % 4)
        {
            case 2: padded += "=="; break;
            case 3: padded += "="; break;
        }

        return Convert.FromBase64String(padded);
    }
}
