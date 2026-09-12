using Microsoft.Extensions.Options;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class UserProfileProvider : IUserProfileProvider
{
    private readonly ISqlExecutor _sqlExecutor;
    private readonly byte[] _key;

    public UserProfileProvider(ISqlExecutor sqlExecutor, IOptions<EncryptionOptions> encryptionOptions)
    {
        _sqlExecutor = sqlExecutor;
        _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);
    }

    public Task<UserProfileModel?> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_UserProfile_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader => await reader.ReadAsync(cancellationToken) ? UserProfileRowMapper.MapUserProfile(reader, _key) : null,
            cancellationToken);

    public async Task<UserProfileModel> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default) =>
        await _sqlExecutor.QueryAsync(
            "dbo.usp_UserProfile_Upsert",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Gender", FieldCipher.EncryptString(request.Gender, _key)),
                SqlParameterBuilder.Create("@AgeYears", FieldCipher.EncryptInt(request.AgeYears, _key)),
                SqlParameterBuilder.Create("@HeightCm", FieldCipher.EncryptDecimal(request.HeightCm, _key)),
                SqlParameterBuilder.Create("@WeightKg", FieldCipher.EncryptDecimal(request.WeightKg, _key)),
                SqlParameterBuilder.Create("@Goal", FieldCipher.EncryptString(request.Goal, _key))
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? UserProfileRowMapper.MapUserProfile(reader, _key) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_UserProfile_Upsert did not return a row.");
}
