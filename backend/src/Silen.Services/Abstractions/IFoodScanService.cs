using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>AI meal-photo scanning for the meal tracker: the photo goes to a vision model,
/// which returns the likely ingredients with portions and per-100 g nutrition. Advanced
/// tier only, a few scans per local day, and only with AI data-sharing consent.</summary>
public interface IFoodScanService
{
    /// <summary>Largest photo accepted. The app sends a ~1024 px JPEG, far below this.</summary>
    const int MaxImageBytes = 5 * 1024 * 1024;

    Task<ServiceResult<FoodScanQuotaDto>> GetQuotaAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Scans <paramref name="image"/> (JPEG, PNG or WebP). <paramref name="mealName"/> is
    /// the name the user gave the meal, passed to the model as a hint.</summary>
    Task<ServiceResult<FoodScanResultDto>> ScanAsync(
        Guid userId, byte[] image, string? mealName, CancellationToken cancellationToken = default);
}
