using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IUserProfileProvider
{
    Task<UserProfileModel?> GetAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<UserProfileModel> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default);
}
