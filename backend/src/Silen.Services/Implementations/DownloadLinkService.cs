using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Authorization;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IDownloadLinkService"/>
/// <remarks>
/// The App Store hands an installed app nothing about the page that sent the user
/// there, so the match is by network: the page's visit and the app's first device
/// login usually come from the same phone on the same Wi-Fi or carrier address
/// within minutes. It is an estimate - iCloud Private Relay or switching networks
/// between scan and first launch loses the match (the install then simply counts
/// as unattributed), and two phones on one gym Wi-Fi can swap credit between
/// themselves, which still lands on the right gym.
///
/// The address itself is never stored: only an HMAC of it (IPv6 cut to its /64,
/// which is what one phone keeps across its rotating privacy addresses), and that
/// hash is wiped once matched or once it is too old to match.
/// </remarks>
public sealed partial class DownloadLinkService(
    IDownloadLinksProvider downloadLinksProvider,
    IAdminProvider adminProvider,
    IAdminRbacProvider adminRbacProvider,
    IOptions<JwtOptions> jwtOptions,
    ILogger<DownloadLinkService> logger) : IDownloadLinkService
{
    /// <summary>How long after opening the page an install is still credited to it.</summary>
    public const int AttributionWindowHours = 72;

    /// <summary>Only an account this new can claim a visit, so a returning user's
    /// device login never takes someone else's.</summary>
    public const int MaxAccountAgeMinutes = 15;

    /// <summary>The network hash outlives the window a little, for clock skew and late first launches.</summary>
    private const int RetainHashHours = AttributionWindowHours + 24;

    private const int LeadLimit = 500;

    private static readonly HashSet<string> Platforms = new(StringComparer.Ordinal) { "ios", "android", "desktop" };

    private readonly byte[] _hashKey = SHA256.HashData(
        Encoding.UTF8.GetBytes("silafit-download-attribution:" + jwtOptions.Value.SigningKey));

    public Task<ServiceResult<bool>> RecordVisitAsync(
        DownloadVisitRequest request, IPAddress? clientIp, string? userAgent, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var platform = (request.Platform ?? string.Empty).Trim().ToLowerInvariant();
            if (!Platforms.Contains(platform))
            {
                throw new ValidationException($"Download visit with unknown platform '{request.Platform}'.", "Unknown platform.");
            }

            var source = NormalizeSource(request.Source);
            await downloadLinksProvider.RecordVisitAsync(
                source,
                request.VisitorId is { } id && id != Guid.Empty ? id : null,
                platform,
                DescribeDevice(userAgent),
                platform == "desktop" ? null : HashAddress(clientIp),
                RetainHashHours,
                cancellationToken);
            return true;
        });

    public async Task ClaimInstallAsync(Guid userId, IPAddress? clientIp, string? platform, CancellationToken cancellationToken = default)
    {
        var ipHash = HashAddress(clientIp);
        if (ipHash is null || userId == Guid.Empty)
        {
            return;
        }

        var normalizedPlatform = platform?.Trim().ToLowerInvariant();
        if (normalizedPlatform is not ("ios" or "android"))
        {
            normalizedPlatform = null;
        }

        try
        {
            var (matched, sourceCode) = await downloadLinksProvider.ClaimInstallAsync(
                userId, ipHash, normalizedPlatform, AttributionWindowHours, MaxAccountAgeMinutes, cancellationToken);
            if (matched)
            {
                logger.LogInformation("Credited a new install to download link {Source}.", sourceCode ?? "(untagged)");
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Could not credit a new install to a download link.");
        }
    }

    public Task<ServiceResult<DownloadLinkReportModel>> GetReportAsync(
        string? sessionToken, int days, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await AdminPermissionGuard.RequireAsync(
                adminProvider, adminRbacProvider, sessionToken, AdminPermissions.UsersRead, null, cancellationToken);

            DateTime? fromUtc = days > 0 ? DateTime.UtcNow.Date.AddDays(-Math.Min(days, 3650) + 1) : null;
            return await downloadLinksProvider.GetReportAsync(fromUtc, LeadLimit, cancellationToken);
        });

    /// <summary>Lower-case slug or nothing. The database decides whether it is a known source.</summary>
    internal static string? NormalizeSource(string? source)
    {
        var value = source?.Trim().ToLowerInvariant();
        return !string.IsNullOrEmpty(value) && value.Length <= 40 && SourcePattern().IsMatch(value) ? value : null;
    }

    /// <summary>The bytes that identify one phone's network: the IPv4 address, or the /64
    /// prefix of an IPv6 one.</summary>
    internal byte[]? HashAddress(IPAddress? address)
    {
        if (address is null)
        {
            return null;
        }

        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        var bytes = address.GetAddressBytes();
        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            bytes = bytes[..8];
        }

        return HMACSHA256.HashData(_hashKey, bytes);
    }

    /// <summary>A short, human label for the report ("iPhone · iOS 18.1 · Instagram app").
    /// Coarse on purpose: model and OS version only, nothing that identifies the person.</summary>
    internal static string? DescribeDevice(string? userAgent)
    {
        if (string.IsNullOrWhiteSpace(userAgent))
        {
            return null;
        }

        string? device;
        if (IosPattern().Match(userAgent) is { Success: true } ios)
        {
            var kind = userAgent.Contains("iPad", StringComparison.Ordinal) ? "iPad" : "iPhone";
            device = $"{kind} · iOS {ios.Groups[1].Value}.{ios.Groups[2].Value}";
        }
        else if (AndroidPattern().Match(userAgent) is { Success: true } android)
        {
            device = $"Android {android.Groups[1].Value}";
        }
        else if (userAgent.Contains("Macintosh", StringComparison.Ordinal))
        {
            device = "Mac";
        }
        else if (userAgent.Contains("Windows", StringComparison.Ordinal))
        {
            device = "Windows";
        }
        else if (userAgent.Contains("Linux", StringComparison.Ordinal))
        {
            device = "Linux";
        }
        else
        {
            device = "Other";
        }

        // Scans from a profile link often open inside the social app's own browser.
        if (userAgent.Contains("Instagram", StringComparison.Ordinal))
        {
            device += " · Instagram app";
        }
        else if (userAgent.Contains("musical_ly", StringComparison.Ordinal)
                 || userAgent.Contains("TikTok", StringComparison.Ordinal)
                 || userAgent.Contains("BytedanceWebview", StringComparison.Ordinal))
        {
            device += " · TikTok app";
        }
        else if (userAgent.Contains("FBAN", StringComparison.Ordinal) || userAgent.Contains("FBAV", StringComparison.Ordinal))
        {
            device += " · Facebook app";
        }

        return device.Length <= 60 ? device : device[..60];
    }

    [GeneratedRegex("^[a-z0-9]+(?:-[a-z0-9]+)*$")]
    private static partial Regex SourcePattern();

    [GeneratedRegex(@"(?:iPhone|CPU) OS (\d+)_(\d+)")]
    private static partial Regex IosPattern();

    [GeneratedRegex(@"Android (\d+(?:\.\d+)?)")]
    private static partial Regex AndroidPattern();
}
