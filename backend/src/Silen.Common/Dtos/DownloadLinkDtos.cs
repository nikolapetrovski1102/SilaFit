using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

/// <summary>One open of the website's download page (website/js/download.js), sent as a
/// beacon right before the page hands the visitor to the store.</summary>
public sealed class DownloadVisitRequest
{
    /// <summary>The link's <c>?src=</c> tag, e.g. "crooks-gym". Unknown or missing tags
    /// are recorded as an untagged visit.</summary>
    [StringLength(80)]
    public string? Source { get; set; }

    /// <summary>A random id the page keeps in the browser, so repeat opens on one
    /// device count once.</summary>
    public Guid? VisitorId { get; set; }

    /// <summary>"ios", "android" or "desktop", as the page detected it (it catches
    /// iPadOS Safari, which claims to be a Mac in its user agent).</summary>
    [Required]
    [StringLength(10)]
    public string Platform { get; set; } = string.Empty;
}
