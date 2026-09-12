using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class UserProfileProvider(ISqlExecutor sqlExecutor) : IUserProfileProvider
{
    public Task<UserProfileModel?> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserProfile_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader => await reader.ReadAsync(cancellationToken) ? UserProfileRowMapper.MapUserProfile(reader) : null,
            cancellationToken);

    public async Task<UserProfileModel> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.usp_UserProfile_Upsert",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Gender", request.Gender),
                SqlParameterBuilder.Create("@AgeYears", request.AgeYears),
                SqlParameterBuilder.Create("@HeightCm", request.HeightCm),
                SqlParameterBuilder.Create("@WeightKg", request.WeightKg),
                SqlParameterBuilder.Create("@Goal", request.Goal)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? UserProfileRowMapper.MapUserProfile(reader) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_UserProfile_Upsert did not return a row.");
}
