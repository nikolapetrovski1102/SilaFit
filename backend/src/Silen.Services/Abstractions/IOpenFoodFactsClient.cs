using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Live product lookup on the Open Food Facts API, for barcodes the last
/// catalog import didn't have (new products, or ones added to OFF since).</summary>
public interface IOpenFoodFactsClient
{
    /// <summary>The product with this barcode, or null when OFF doesn't know it or
    /// can't be reached. Never throws for an upstream failure: a scan falls back to
    /// "add it yourself" rather than an error.</summary>
    Task<OpenFoodFactsProductModel?> GetProductAsync(string barcode, CancellationToken cancellationToken = default);
}
