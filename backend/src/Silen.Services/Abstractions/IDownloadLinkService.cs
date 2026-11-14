using System.Net;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>
/// Tagged download links (https://sila.fitness/download?src=...). The website records
/// every open of the page; the first device login of a freshly installed app is then
/// credited to the newest phone visit from the same network, which lets the console
/// report how many people each partner or profile sent, and how many of them went on
/// to sign up and buy.
/// </summary>
public interface IDownloadLinkService
{
    /// <summary>Records one open of the download page. Never reveals whether the
    /// source tag was recognised.</summary>
    Task<ServiceResult<bool>> RecordVisitAsync(
        DownloadVisitRequest request, IPAddress? clientIp, string? userAgent, CancellationToken cancellationToken = default);

    /// <summary>Credits a just-created app account to the download-link visit that led to
    /// it, if any. Best effort: never throws, so it can never get in the way of sign-in.</summary>
    Task ClaimInstallAsync(Guid userId, IPAddress? clientIp, string? platform, CancellationToken cancellationToken = default);

    /// <summary>The console report over the last <paramref name="days"/> days (0 = all
    /// time). Requires users.read.</summary>
    Task<ServiceResult<DownloadLinkReportModel>> GetReportAsync(
        string? sessionToken, int days, CancellationToken cancellationToken = default);
}
