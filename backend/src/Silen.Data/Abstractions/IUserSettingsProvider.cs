using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IUserSettingsProvider
{
    Task<UserSettingsModel?> GetAsync(Guid userId, CancellationToken cancellationToken = default);

    Task SetNotificationsEnabledAsync(Guid userId, bool enabled, CancellationToken cancellationToken = default);

    Task<UserSettingsModel?> UpdateAsync(Guid userId, UpdateUserSettingsRequest request, CancellationToken cancellationToken = default);
}
