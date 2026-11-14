using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>AI meal-photo scanning for the meal tracker: the photo goes to a vision model,
/// which returns the likely ingredients with portions and per-100 g nutrition. Advanced
/// tier only, a few scans per local day, and only with AI data-sharing consent. The quota
/// also says whether barcode scanning is open (see <see cref="IFoodService.LookupBarcodeAsync"/>).</summary>
public interface IFoodScanService
{
    /// <summary>Largest photo accepted. The app sends a ~1024 px JPEG, far below this.</summary>
    const int MaxImageBytes = 5 * 1024 * 1024;

    /// <summary>Barcode lookups a Free account gets before barcode scanning needs Pro. The
    /// app never shows this count - the next scan after it opens the plans.</summary>
    const int BarcodeTrialLimit = 3;

    Task<ServiceResult<FoodScanQuotaDto>> GetQuotaAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Scans <paramref name="image"/> (JPEG, PNG or WebP). <paramref name="mealName"/> is
    /// the name the user gave the meal, passed to the model as a hint.</summary>
    Task<ServiceResult<FoodScanResultDto>> ScanAsync(
        Guid userId, byte[] image, string? mealName, CancellationToken cancellationToken = default);

    /// <summary>Reads a photo of a package's nutrition table into per-100 g values, to fill
    /// in a product the catalog is missing. Every tier (it grows the catalog for everyone),
    /// with AI data-sharing consent; the endpoint's rate limit bounds the cost.</summary>
    Task<ServiceResult<NutritionLabelResultDto>> ReadLabelAsync(
        Guid userId, byte[] image, CancellationToken cancellationToken = default);
}
