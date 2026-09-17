using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAccountProvider
{
    Task DeleteAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ExportEligibilityModel> TryBeginExportAsync(Guid userId, int cooldownDays, CancellationToken cancellationToken = default);

    Task<AccountExportModel> ExportAsync(Guid userId, CancellationToken cancellationToken = default);
}
