using Silen.Common.Contracts;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAccountService"/>
public sealed class AccountService(IAccountProvider accountProvider) : IAccountService
{
    public Task<ServiceResult<bool>> DeleteAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await accountProvider.DeleteAsync(userId, cancellationToken);
            return true;
        });

    public Task<ServiceResult<AccountExportModel>> ExportAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => accountProvider.ExportAsync(userId, cancellationToken));
}
