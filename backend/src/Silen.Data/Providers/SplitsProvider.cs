using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class SplitsProvider(ISqlExecutor sqlExecutor) : ISplitsProvider
{
    public Task<List<WorkoutSplitModel>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Splits_GetAll",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplit, cancellationToken),
            cancellationToken);

    public Task<(WorkoutSplitModel? Split, List<SplitDayModel> Days, List<SplitDayExerciseModel> Exercises)> GetDetailAsync(
        Guid splitId, Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Splits_GetDetail",
            [SqlParameterBuilder.Create("@SplitId", splitId), SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var split = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSplit, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var days = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplitDay, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var exercises = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplitDayExercise, cancellationToken);
                return (split, days, exercises);
            },
            cancellationToken);

    public Task<ActiveSplitModel?> SetActiveAsync(Guid userId, Guid splitId, bool isAutoAssigned = false, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserActiveSplit_Set",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@SplitId", splitId),
                SqlParameterBuilder.Create("@IsAutoAssigned", isAutoAssigned)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapActiveSplit, cancellationToken),
            cancellationToken);

    public Task<ActiveSplitModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserActiveSplit_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapActiveSplit, cancellationToken),
            cancellationToken);

    /* ----------------------------- user-owned splits ----------------------------- */

    public Task<List<WorkoutSplitModel>> GetOwnedSplitsAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplits_GetOwned",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplit, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserSplitAsync(UserSplitUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplit_Upsert",
            [
                SqlParameterBuilder.Create("@SplitId", request.SplitId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Category", request.Category),
                SqlParameterBuilder.Create("@Level", request.Level),
                SqlParameterBuilder.Create("@DurationDays", request.DurationDays),
                SqlParameterBuilder.Create("@Description", request.Description),
                SqlParameterBuilder.Create("@HeroImageUrl", request.HeroImageUrl),
                SqlParameterBuilder.Create("@RecommendedGoal", request.RecommendedGoal),
                SqlParameterBuilder.Create("@IsAiGenerated", request.IsAiGenerated)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> KeepUserSplitAsync(Guid splitId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplit_Keep",
            [SqlParameterBuilder.Create("@SplitId", splitId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserSplitAsync(Guid splitId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplit_Delete",
            [SqlParameterBuilder.Create("@SplitId", splitId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserSplitDayAsync(UserSplitDayUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplitDay_Upsert",
            [
                SqlParameterBuilder.Create("@SplitDayId", request.SplitDayId),
                SqlParameterBuilder.Create("@SplitId", request.SplitId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayIndex", request.DayIndex),
                SqlParameterBuilder.Create("@Title", request.Title),
                SqlParameterBuilder.Create("@FocusLabel", request.FocusLabel),
                SqlParameterBuilder.Create("@EstimatedMinutes", request.EstimatedMinutes),
                SqlParameterBuilder.Create("@IsRestDay", request.IsRestDay)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserSplitDayAsync(Guid splitDayId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplitDay_Delete",
            [SqlParameterBuilder.Create("@SplitDayId", splitDayId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserSplitDayExerciseAsync(UserSplitDayExerciseUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplitDayExercise_Upsert",
            [
                SqlParameterBuilder.Create("@SplitDayExerciseId", request.SplitDayExerciseId),
                SqlParameterBuilder.Create("@SplitDayId", request.SplitDayId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ExerciseId", request.ExerciseId),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                SqlParameterBuilder.Create("@TargetSets", request.TargetSets),
                SqlParameterBuilder.Create("@TargetRepsLow", request.TargetRepsLow),
                SqlParameterBuilder.Create("@TargetRepsHigh", request.TargetRepsHigh)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserSplitDayExerciseAsync(Guid splitDayExerciseId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSplitDayExercise_Delete",
            [SqlParameterBuilder.Create("@SplitDayExerciseId", splitDayExerciseId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);
}
