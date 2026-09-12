using Microsoft.Extensions.Options;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class BodyweightProvider : IBodyweightProvider
{
    private readonly ISqlExecutor _sqlExecutor;
    private readonly byte[] _key;

    public BodyweightProvider(ISqlExecutor sqlExecutor, IOptions<EncryptionOptions> encryptionOptions)
    {
        _sqlExecutor = sqlExecutor;
        _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);
    }

    public Task<List<BodyweightEntryModel>> LogAsync(Guid userId, decimal weightKg, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Bodyweight_Log",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@WeightKg", FieldCipher.EncryptDecimal(weightKg, _key))],
            reader => SqlResultSetReader.ReadListAsync(reader, r => WorkoutRowMapper.MapBodyweightEntry(r, _key), cancellationToken),
            cancellationToken);

    public Task<List<BodyweightEntryModel>> GetLatestAsync(Guid userId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Bodyweight_GetLatest",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, r => WorkoutRowMapper.MapBodyweightEntry(r, _key), cancellationToken),
            cancellationToken);

    public Task<List<BodyweightEntryModel>> GetInRangeAsync(Guid userId, DateOnly fromDateUtc, DateOnly toDateUtc, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Bodyweight_GetInRange",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.ToDateTime(TimeOnly.MinValue)),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.ToDateTime(TimeOnly.MinValue))
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, r => WorkoutRowMapper.MapBodyweightEntry(r, _key), cancellationToken),
            cancellationToken);
}
