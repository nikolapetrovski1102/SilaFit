using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class AccountProvider : IAccountProvider
{
    private readonly ISqlExecutor _sqlExecutor;
    private readonly byte[] _key;

    public AccountProvider(ISqlExecutor sqlExecutor, IOptions<EncryptionOptions> encryptionOptions)
    {
        _sqlExecutor = sqlExecutor;
        _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);
    }

    public Task DeleteAsync(Guid userId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.ExecuteAsync(
            "dbo.usp_Account_Delete",
            [SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);

    public Task<AccountExportModel> ExportAsync(Guid userId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Account_Export",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var account = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapAccount, cancellationToken)
                    ?? throw new InvalidOperationException($"usp_Account_Export returned no account row for user '{userId}'.");

                await reader.NextResultAsync(cancellationToken);
                var identities = await SqlResultSetReader.ReadListAsync(reader, AccountRowMapper.MapLinkedIdentity, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var profile = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, r => UserProfileRowMapper.MapUserProfile(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var settings = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, SettingsRowMapper.MapSettings, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var nutritionTargets = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, r => MealPlanningRowMapper.MapNutritionTargets(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var bodyweightHistory = await SqlResultSetReader.ReadListAsync(reader, r => WorkoutRowMapper.MapBodyweightEntry(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var hydrationHistory = await SqlResultSetReader.ReadListAsync(reader, AccountRowMapper.MapHydrationEntry, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var mealLogs = await SqlResultSetReader.ReadListAsync(reader, r => MealPlanningRowMapper.MapMealLog(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var workoutSessions = await SqlResultSetReader.ReadListAsync(reader, AccountRowMapper.MapWorkoutSessionHistory, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var workoutSetLogs = await SqlResultSetReader.ReadListAsync(reader, AccountRowMapper.MapWorkoutSetLogEntry, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var subscription = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSubscription, cancellationToken);

                return new AccountExportModel
                {
                    Account = account,
                    LinkedIdentities = identities,
                    Profile = profile,
                    Settings = settings,
                    NutritionTargets = nutritionTargets,
                    BodyweightHistory = bodyweightHistory,
                    HydrationHistory = hydrationHistory,
                    MealLogs = mealLogs,
                    WorkoutSessions = workoutSessions,
                    WorkoutSetLogs = workoutSetLogs,
                    Subscription = subscription
                };
            },
            cancellationToken);
}
