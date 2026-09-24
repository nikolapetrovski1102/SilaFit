using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface ISettingsService
{
    Task<ServiceResult<UserSettingsModel>> GetAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserSettingsModel>> UpdateAsync(Guid userId, UpdateUserSettingsRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserSettingsModel>> SetAiDataConsentAsync(Guid userId, bool granted, CancellationToken cancellationToken = default);
}
