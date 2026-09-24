using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAccountProvider
{
    Task DeleteAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ExportEligibilityModel> TryBeginExportAsync(Guid userId, int cooldownDays, CancellationToken cancellationToken = default);

    Task<AccountExportModel> ExportAsync(Guid userId, CancellationToken cancellationToken = default);

    Task SetAppleRefreshTokenAsync(Guid userId, string refreshToken, CancellationToken cancellationToken = default);

    /// <summary>The user's stored Sign in with Apple refresh token, or null when there is none.</summary>
    Task<string?> GetAppleRefreshTokenAsync(Guid userId, CancellationToken cancellationToken = default);
}
