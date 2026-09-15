using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAccountProvider
{
    Task DeleteAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<AccountExportModel> ExportAsync(Guid userId, CancellationToken cancellationToken = default);
}
