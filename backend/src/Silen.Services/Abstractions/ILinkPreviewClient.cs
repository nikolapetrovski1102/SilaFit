using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Reads a public TikTok post's caption, creator and thumbnail through TikTok's
/// oEmbed endpoint - the documented, key-free way to embed a post. The video itself is
/// never downloaded.</summary>
public interface ILinkPreviewClient
{
    /// <summary>Follows a short link (vm.tiktok.com/...) to the post, then reads its oEmbed.
    /// Null when the post doesn't exist, is private, or TikTok didn't answer.</summary>
    Task<LinkPreviewModel?> GetTikTokPreviewAsync(Uri url, CancellationToken cancellationToken = default);
}
