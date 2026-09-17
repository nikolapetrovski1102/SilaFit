namespace Silen.Services.Abstractions;

/// <summary>
/// A file the caller wants stored, described with plain BCL types (rather than
/// <c>IFormFile</c>) so this layer doesn't need an ASP.NET Core dependency -
/// the API controller is what reads the multipart upload apart.
/// </summary>
/// <param name="Content">Readable, seekable-not-required stream positioned at the start of the file.</param>
/// <param name="FileName">Original file name, used only to recover the extension.</param>
/// <param name="ContentType">Client-supplied MIME type, if any.</param>
/// <param name="LengthBytes">Size of <paramref name="Content"/> in bytes.</param>
public sealed record ImageUploadRequest(Stream Content, string FileName, string? ContentType, long LengthBytes);

/// <summary>Validates and persists an uploaded image, handing back a public URL for it.</summary>
public interface IImageUploadService
{
    /// <summary>
    /// Throws <see cref="Silen.Common.Exceptions.ValidationException"/> when the upload is
    /// missing, oversized, or not an accepted image type.
    /// </summary>
    Task<string> SaveAsync(ImageUploadRequest upload, CancellationToken cancellationToken = default);
}
