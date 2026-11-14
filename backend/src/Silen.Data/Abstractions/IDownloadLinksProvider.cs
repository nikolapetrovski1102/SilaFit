using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Tagged download links: page opens (dbo.DownloadVisits), installs credited to
/// them, and the console report over both.</summary>
public interface IDownloadLinksProvider
{
    /// <summary>Records one open of the download page. An unknown <paramref name="sourceCode"/>
    /// is stored as untagged; desktop visits never keep <paramref name="ipHash"/>.</summary>
    Task RecordVisitAsync(
        string? sourceCode, Guid? visitorId, string platform, string? deviceLabel, byte[]? ipHash,
        int retainHashHours, CancellationToken cancellationToken = default);

    /// <summary>Credits a just-created account to the newest unmatched phone visit from the
    /// same network. Returns whether a visit was claimed, and its source code.</summary>
    Task<(bool Matched, string? SourceCode)> ClaimInstallAsync(
        Guid userId, byte[] ipHash, string? platform, int windowHours, int maxAccountAgeMinutes,
        CancellationToken cancellationToken = default);

    Task<DownloadLinkReportModel> GetReportAsync(DateTime? fromUtc, int leadLimit, CancellationToken cancellationToken = default);
}
