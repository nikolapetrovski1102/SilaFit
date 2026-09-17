using Microsoft.Extensions.Options;
using Silen.Common.Exceptions;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IImageUploadService"/>
public sealed class ImageUploadService(IOptions<ImageUploadOptions> options) : IImageUploadService
{
    // Kept narrow on purpose - these are the formats the app/console actually
    // render; anything else (svg, gif, heic, ...) is rejected rather than passed
    // through to a browser <img> tag untested.
    private static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".png", ".webp"
    };

    public async Task<string> SaveAsync(ImageUploadRequest upload, CancellationToken cancellationToken = default)
    {
        var settings = options.Value;

        if (upload.LengthBytes <= 0)
        {
            throw new ValidationException("Image upload called with an empty file.", "Choose an image to upload.");
        }
        if (upload.LengthBytes > settings.MaxFileSizeBytes)
        {
            throw new ValidationException(
                $"Image upload of {upload.LengthBytes} bytes exceeds the {settings.MaxFileSizeBytes} byte limit.",
                $"That image is too large - the limit is {settings.MaxFileSizeBytes / (1024 * 1024)}MB.");
        }

        var extension = Path.GetExtension(upload.FileName);
        if (string.IsNullOrEmpty(extension) || !AllowedExtensions.Contains(extension))
        {
            throw new ValidationException(
                $"Image upload rejected for extension '{extension}'.",
                "Only JPG, PNG and WEBP images are accepted.");
        }

        Directory.CreateDirectory(settings.StoragePath);

        // Random name: never trust the client's file name past its extension -
        // it's shown back to nobody and would otherwise be a path-traversal/
        // collision vector.
        var fileName = $"{Guid.NewGuid():N}{extension.ToLowerInvariant()}";
        var fullPath = Path.Combine(settings.StoragePath, fileName);

        await using (var destination = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write))
        {
            await upload.Content.CopyToAsync(destination, cancellationToken);
        }

        return $"{settings.PublicBaseUrl.TrimEnd('/')}/{fileName}";
    }
}
