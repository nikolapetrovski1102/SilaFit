namespace Silen.Common.Models;

/// <summary>Outcome of claiming a shared-link scan (dbo.usp_LinkScan_TryReserve).</summary>
public sealed class LinkScanReservationModel
{
    public bool Allowed { get; set; }

    /// <summary>Scans counted against the limit that applied, including this one when allowed:
    /// today's scans of that kind for a paid tier, lifetime trial scans for Free.</summary>
    public int Used { get; set; }

    public long? LinkScanId { get; set; }
}

/// <summary>How many shared-link scans the user has made (dbo.usp_LinkScan_Usage).</summary>
public sealed class LinkScanUsageModel
{
    public int WorkoutToday { get; set; }
    public int MealToday { get; set; }
    public int TrialUsed { get; set; }
}

/// <summary>What a public post says about itself, read from the provider's oEmbed endpoint.</summary>
public sealed class LinkPreviewModel
{
    /// <summary>"tiktok".</summary>
    public string Provider { get; set; } = string.Empty;

    /// <summary>The provider's id for the video - the cache key.</summary>
    public string VideoId { get; set; } = string.Empty;

    /// <summary>The canonical post URL, after following any short link.</summary>
    public string Url { get; set; } = string.Empty;

    /// <summary>The post's caption (oEmbed calls it the title).</summary>
    public string Caption { get; set; } = string.Empty;
    public string AuthorName { get; set; } = string.Empty;
    public string? ThumbnailUrl { get; set; }
}
