using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>A grocery partner's product catalog (paket.mk), asked about a scanned barcode
/// after our own catalog and before Open Food Facts: the partner knows what is actually on
/// Macedonian shelves. Switched on per provider in the admin console.</summary>
public interface IPartnerFoodCatalogClient
{
    /// <summary>The product with this barcode, or null when no partner catalog is switched on,
    /// the partner doesn't stock it, or it can't be reached. Never throws for an upstream
    /// failure: the lookup moves on to Open Food Facts.</summary>
    Task<PartnerFoodProductModel?> GetProductAsync(string barcode, CancellationToken cancellationToken = default);
}

/// <summary>A partner's product, with the partner's name to store as its source.</summary>
public sealed record PartnerFoodProductModel(string SourceName, OpenFoodFactsProductModel Product);
