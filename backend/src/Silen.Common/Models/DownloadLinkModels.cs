namespace Silen.Common.Models;

/// <summary>The console's download-links report (dbo.usp_Download_Report).</summary>
public sealed class DownloadLinkReportModel
{
    /// <summary>Start of the reported period; null for all time.</summary>
    public DateTime? FromUtc { get; set; }

    public List<DownloadSourceStatsModel> Sources { get; set; } = [];

    public List<DownloadLeadModel> Leads { get; set; } = [];
}

/// <summary>One tagged link (or the untagged row, <see cref="SourceCode"/> null) and its funnel.</summary>
public sealed class DownloadSourceStatsModel
{
    public string? SourceCode { get; set; }
    public string Label { get; set; } = string.Empty;

    /// <summary>"partner", "social" or "direct" (the untagged row).</summary>
    public string Channel { get; set; } = string.Empty;
    public bool IsActive { get; set; }

    /// <summary>Every open of the page through this link.</summary>
    public int Opens { get; set; }

    /// <summary>Distinct browsers among <see cref="Opens"/>.</summary>
    public int UniqueDevices { get; set; }
    public int IosOpens { get; set; }
    public int AndroidOpens { get; set; }
    public int DesktopOpens { get; set; }
    public DateTime? LastVisitAtUtc { get; set; }

    /// <summary>New app accounts credited to a visit through this link.</summary>
    public int Installs { get; set; }

    /// <summary>Of <see cref="Installs"/>, those that went on to register.</summary>
    public int SignedUp { get; set; }

    /// <summary>Of <see cref="Installs"/>, those with any store purchase.</summary>
    public int Purchased { get; set; }

    /// <summary>Of <see cref="Installs"/>, those with a live store subscription right now.</summary>
    public int PayingNow { get; set; }
}

/// <summary>One install credited to a download-link visit, and how far it got.</summary>
public sealed class DownloadLeadModel
{
    public string? SourceCode { get; set; }
    public string SourceLabel { get; set; } = string.Empty;
    public string Platform { get; set; } = string.Empty;
    public string? DeviceLabel { get; set; }
    public DateTime VisitedAtUtc { get; set; }
    public DateTime InstalledAtUtc { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string AccountTier { get; set; } = string.Empty;
    public bool Purchased { get; set; }
    public bool PayingNow { get; set; }
    public string? ActivePlanCode { get; set; }
}
