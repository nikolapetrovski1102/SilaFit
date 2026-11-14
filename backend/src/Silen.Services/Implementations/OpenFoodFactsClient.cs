using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Silen.Common.Models;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IOpenFoodFactsClient"/>
/// <remarks>Read-only v2 product endpoint, no key needed. OFF asks API clients to name
/// themselves in the User-Agent (set where the HttpClient is registered). Data is ODbL
/// and images CC-BY-SA: the app credits Open Food Facts wherever it shows them.</remarks>
public sealed class OpenFoodFactsClient(HttpClient httpClient, ILogger<OpenFoodFactsClient> logger) : IOpenFoodFactsClient
{
    public const string BaseUrl = "https://world.openfoodfacts.org/api/v2/product/";

    private const string Fields =
        "code,product_name,product_name_en,product_name_mk,brands,image_front_small_url,image_front_url,serving_quantity,nutriments";

    public async Task<OpenFoodFactsProductModel?> GetProductAsync(string barcode, CancellationToken cancellationToken = default)
    {
        try
        {
            using var response = await httpClient
                .GetAsync($"{BaseUrl}{Uri.EscapeDataString(barcode)}?fields={Fields}", cancellationToken)
                .ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return null;
            }

            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("Open Food Facts returned {StatusCode} for a barcode lookup.", (int)response.StatusCode);
                return null;
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            return Parse(barcode, document.RootElement);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException
                                   || (ex is TaskCanceledException && !cancellationToken.IsCancellationRequested))
        {
            logger.LogWarning("Open Food Facts barcode lookup failed: {Error}.", ex.GetType().Name);
            return null;
        }
    }

    /// <summary>Maps a v2 product response. Status 0 (unknown barcode) gives null.</summary>
    public static OpenFoodFactsProductModel? Parse(string barcode, JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("product", out var product) || product.ValueKind != JsonValueKind.Object
            || (root.TryGetProperty("status", out var status) && Number(status) == 0))
        {
            return null;
        }

        var nutriments = product.TryGetProperty("nutriments", out var n) && n.ValueKind == JsonValueKind.Object
            ? n
            : default;

        return new OpenFoodFactsProductModel
        {
            Barcode = barcode,
            Name = FirstText(product, "product_name", "product_name_en", "product_name_mk"),
            BrandName = FirstBrand(Text(product, "brands")),
            ImageUrl = FirstText(product, "image_front_small_url", "image_front_url"),
            ServingSizeG = Positive(NumberProperty(product, "serving_quantity")),
            CaloriesKcal = NumberProperty(nutriments, "energy-kcal_100g"),
            ProteinG = NumberProperty(nutriments, "proteins_100g"),
            CarbohydrateG = NumberProperty(nutriments, "carbohydrates_100g"),
            FatG = NumberProperty(nutriments, "fat_100g"),
            FiberG = NumberProperty(nutriments, "fiber_100g"),
            SugarG = NumberProperty(nutriments, "sugars_100g"),
            // OFF reports sodium in grams; the catalog stores milligrams.
            SodiumMg = NumberProperty(nutriments, "sodium_100g") is { } sodium ? sodium * 1000m : null
        };
    }

    private static string? FirstText(JsonElement element, params string[] names) =>
        names.Select(name => Text(element, name)).FirstOrDefault(value => value is not null);

    private static string? Text(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.String
        && !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()!.Trim()
            : null;

    /// <summary>"Vitaminka, Swisslion" -> "Vitaminka": OFF lists the brand and its owners.</summary>
    private static string? FirstBrand(string? brands) =>
        brands?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault();

    private static decimal? NumberProperty(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) ? Number(value) : null;

    /// <summary>OFF sends numbers as JSON numbers or as strings, depending on the field's history.</summary>
    private static decimal? Number(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetDecimal(out var number) => number,
        JsonValueKind.String when decimal.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) => parsed,
        _ => null
    };

    private static decimal? Positive(decimal? value) => value > 0 ? value : null;
}
