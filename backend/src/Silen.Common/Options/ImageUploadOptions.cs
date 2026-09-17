namespace Silen.Common.Options;

/// <summary>
/// Bound from the "ImageUploads" configuration section. Backs the admin console's
/// split hero-image upload: files are written to disk at <see cref="StoragePath"/>
/// and handed back as a URL built from <see cref="PublicBaseUrl"/>. In production
/// that base URL is the images.sila.fitness nginx vhost, which serves the same
/// directory directly off disk (see deploy/nginx-sila.fitness.conf) - the API is
/// only ever hit for the upload itself, never for serving the image back out.
/// </summary>
public sealed class ImageUploadOptions
{
    public const string SectionName = "ImageUploads";

    /// <summary>Directory files are written to. Relative paths resolve against the API's working directory.</summary>
    public string StoragePath { get; set; } = "uploads";

    /// <summary>Prefix returned URLs are built from, e.g. "https://images.sila.fitness". No trailing slash.</summary>
    public string PublicBaseUrl { get; set; } = "http://localhost:5010/uploads";

    public long MaxFileSizeBytes { get; set; } = 8 * 1024 * 1024;
}
