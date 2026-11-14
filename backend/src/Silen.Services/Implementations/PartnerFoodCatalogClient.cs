using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IPartnerFoodCatalogClient"/>
/// <remarks>
/// The catalog link, key and on/off switch live on the provider in the admin console
/// (Providers > the partner > Barcode catalog). The partner's API doesn't exist yet, so this
/// reads the contract we'd ask them for: <c>GET</c> the catalog link answering 404 for an unknown code, or 200 with
/// <code>
/// { "name": "Ajvar blagi", "brandName": "Zito", "imageUrl": "https://...", "productUrl": "https://...",
///   "servingSizeG": 30, "caloriesKcal": 120, "proteinG": 2, "carbohydrateG": 10, "fatG": 8,
///   "fiberG": 1.5, "sugarG": 6, "sodiumMg": 400 }
/// </code>
/// with every nutrient per 100 g. If their real API differs, <see cref="Parse"/> is the only
/// thing to change.
/// </remarks>
public sealed class PartnerFoodCatalogClient(
    HttpClient httpClient,
    ISupplementProvidersProvider providersProvider,
    ILogger<PartnerFoodCatalogClient> logger) : IPartnerFoodCatalogClient
{
    public const string BarcodePlaceholder = SupplementProviderService.BarcodePlaceholder;

    public async Task<PartnerFoodProductModel?> GetProductAsync(string barcode, CancellationToken cancellationToken = default)
    {
        var catalog = await providersProvider.GetBarcodeCatalogAsync(cancellationToken);
        if (catalog is null
            || !catalog.ProductUrl.Contains(BarcodePlaceholder, StringComparison.Ordinal)
            || !catalog.ProductUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var sourceName = catalog.Name;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get,
                catalog.ProductUrl.Replace(BarcodePlaceholder, Uri.EscapeDataString(barcode), StringComparison.Ordinal));
            if (!string.IsNullOrWhiteSpace(catalog.ApiKey))
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", catalog.ApiKey);
            }

            using var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return null;
            }

            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("{Partner} returned {StatusCode} for a barcode lookup.", sourceName, (int)response.StatusCode);
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            return Parse(barcode, document.RootElement) is { } product
                ? new PartnerFoodProductModel(sourceName, product)
                : null;
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException
                                   || (ex is TaskCanceledException && !cancellationToken.IsCancellationRequested))
        {
            logger.LogWarning("{Partner} barcode lookup failed: {Error}.", sourceName, ex.GetType().Name);
            return null;
        }
    }

    /// <summary>Maps the partner's product JSON (see the class remarks). No name gives null.</summary>
    public static OpenFoodFactsProductModel? Parse(string barcode, JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var name = Text(root, "name");
        if (name is null)
        {
            return null;
        }

        return new OpenFoodFactsProductModel
        {
            Barcode = barcode,
            Name = name,
            BrandName = Text(root, "brandName"),
            ImageUrl = HttpsOrNull(Text(root, "imageUrl")),
            SourceUrl = HttpsOrNull(Text(root, "productUrl")),
            ServingSizeG = Number(root, "servingSizeG"),
            CaloriesKcal = Number(root, "caloriesKcal"),
            ProteinG = Number(root, "proteinG"),
            CarbohydrateG = Number(root, "carbohydrateG"),
            FatG = Number(root, "fatG"),
            FiberG = Number(root, "fiberG"),
            SugarG = Number(root, "sugarG"),
            SodiumMg = Number(root, "sodiumMg")
        };
    }

    private static string? Text(JsonElement root, string property) =>
        root.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()!.Trim()
            : null;

    private static decimal? Number(JsonElement root, string property)
    {
        if (!root.TryGetProperty(property, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetDecimal(out var number) => number,
            JsonValueKind.String when decimal.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) => parsed,
            _ => null
        };
    }

    private static string? HttpsOrNull(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? url : null;
}
