using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Silen.Common.Models;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ILinkPreviewClient"/>
/// <remarks>The HttpClient is registered with automatic redirects off, so every hop of a short
/// link is checked against <see cref="TikTokLinks.IsTikTokHost"/> before it is followed - a
/// shared link can never steer the server to another host.</remarks>
public sealed class TikTokPreviewClient(HttpClient httpClient, ILogger<TikTokPreviewClient> logger) : ILinkPreviewClient
{
    private const int MaxRedirects = 5;
    private const int MaxCaptionLength = 2200;
    private const string OEmbedEndpoint = "https://www.tiktok.com/oembed?url=";

    // TikTok answers short links with a redirect only for a browser-like agent.
    private const string UserAgent = "Mozilla/5.0 (compatible; SilaFitLinkPreview/1.0; +https://sila.fitness)";

    public async Task<LinkPreviewModel?> GetTikTokPreviewAsync(Uri url, CancellationToken cancellationToken = default)
    {
        try
        {
            var postUrl = TikTokLinks.VideoId(url) is null ? await ResolveShortLinkAsync(url, cancellationToken) : url;
            if (postUrl is null)
            {
                return null;
            }

            using var request = new HttpRequestMessage(HttpMethod.Get, OEmbedEndpoint + Uri.EscapeDataString(postUrl.GetLeftPart(UriPartial.Path)));
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            using var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogInformation("TikTok oEmbed answered {StatusCode} for {Url}.", (int)response.StatusCode, postUrl);
                return null;
            }

            await using var body = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            var oembed = await JsonSerializer.DeserializeAsync<OEmbed>(body, cancellationToken: cancellationToken).ConfigureAwait(false);
            var videoId = TikTokLinks.VideoId(postUrl) ?? oembed?.EmbedProductId;
            if (oembed is null || string.IsNullOrWhiteSpace(videoId))
            {
                return null;
            }

            var caption = (oembed.Title ?? string.Empty).Trim();
            return new LinkPreviewModel
            {
                Provider = TikTokLinks.Provider,
                VideoId = videoId,
                Url = postUrl.GetLeftPart(UriPartial.Path),
                Caption = caption.Length > MaxCaptionLength ? caption[..MaxCaptionLength] : caption,
                AuthorName = (oembed.AuthorName ?? string.Empty).Trim(),
                ThumbnailUrl = Uri.TryCreate(oembed.ThumbnailUrl, UriKind.Absolute, out var thumb) && thumb.Scheme == Uri.UriSchemeHttps
                    ? thumb.ToString()
                    : null
            };
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
        {
            logger.LogInformation(ex, "TikTok preview failed for {Url}.", url);
            return null;
        }
    }

    private async Task<Uri?> ResolveShortLinkAsync(Uri url, CancellationToken cancellationToken)
    {
        var current = url;
        for (var hop = 0; hop < MaxRedirects; hop++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            using var response = await httpClient
                .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);

            if (response.StatusCode is not (HttpStatusCode.Moved or HttpStatusCode.Redirect or HttpStatusCode.RedirectMethod
                or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
                || response.Headers.Location is not { } location)
            {
                return null;
            }

            var next = location.IsAbsoluteUri ? location : new Uri(current, location);
            if (!TikTokLinks.IsTikTokHost(next))
            {
                logger.LogInformation("TikTok short link {Url} redirected off TikTok to {Host}.", url, next.Host);
                return null;
            }

            if (TikTokLinks.VideoId(next) is not null)
            {
                return next;
            }

            current = next;
        }

        return null;
    }

    private sealed class OEmbed
    {
        [JsonPropertyName("title")]
        public string? Title { get; set; }

        [JsonPropertyName("author_name")]
        public string? AuthorName { get; set; }

        [JsonPropertyName("thumbnail_url")]
        public string? ThumbnailUrl { get; set; }

        [JsonPropertyName("embed_product_id")]
        public string? EmbedProductId { get; set; }
    }
}
