using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IUserProfileService
{
    Task<ServiceResult<UserProfileModel>> GetAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserProfileModel>> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default);
}
