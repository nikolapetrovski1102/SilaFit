using Silen.Common.Contracts;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IAccountService
{
    Task<ServiceResult<bool>> DeleteAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AccountExportRequestResultModel>> ExportAsync(Guid userId, CancellationToken cancellationToken = default);
}
