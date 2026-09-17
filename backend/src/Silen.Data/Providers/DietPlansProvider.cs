using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IDietPlansProvider"/>
public sealed class DietPlansProvider(ISqlExecutor sqlExecutor) : IDietPlansProvider
{
    public Task<List<DietPlanModel>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_DietPlans_GetAll",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, DietPlanRowMapper.MapDietPlan, cancellationToken),
            cancellationToken);

    public Task<(DietPlanModel? Plan, List<DietPlanDayModel> Days, List<DietPlanMealModel> Meals)> GetDetailAsync(
        Guid dietPlanId, Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_DietPlans_GetDetail",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId), SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var plan = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, DietPlanRowMapper.MapDietPlan, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var days = await SqlResultSetReader.ReadListAsync(reader, DietPlanRowMapper.MapDietPlanDay, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var meals = await SqlResultSetReader.ReadListAsync(reader, DietPlanRowMapper.MapDietPlanMeal, cancellationToken);
                return (plan, days, meals);
            },
            cancellationToken);

    /* --------------------------- user-owned diet plans --------------------------- */

    public Task<List<DietPlanModel>> GetOwnedAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlans_GetOwned",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, DietPlanRowMapper.MapDietPlan, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserDietPlanAsync(UserDietPlanUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlan_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanId", request.DietPlanId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Description", request.Description),
                SqlParameterBuilder.Create("@HeroImageUrl", request.HeroImageUrl),
                SqlParameterBuilder.Create("@PeriodType", request.PeriodType),
                SqlParameterBuilder.Create("@DurationDays", request.DurationDays),
                SqlParameterBuilder.Create("@IsAiGenerated", request.IsAiGenerated)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> KeepUserDietPlanAsync(Guid dietPlanId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlan_Keep",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserDietPlanAsync(Guid dietPlanId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlan_Delete",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserDietPlanDayAsync(UserDietPlanDayUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlanDay_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanDayId", request.DietPlanDayId),
                SqlParameterBuilder.Create("@DietPlanId", request.DietPlanId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayIndex", request.DayIndex),
                SqlParameterBuilder.Create("@Title", request.Title)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserDietPlanDayAsync(Guid dietPlanDayId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlanDay_Delete",
            [SqlParameterBuilder.Create("@DietPlanDayId", dietPlanDayId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertUserDietPlanMealAsync(UserDietPlanMealUpsertRequest request, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlanMeal_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanMealId", request.DietPlanMealId),
                SqlParameterBuilder.Create("@DietPlanDayId", request.DietPlanDayId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@MealType", request.MealType),
                SqlParameterBuilder.Create("@MealSuggestionId", request.MealSuggestionId),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteUserDietPlanMealAsync(Guid dietPlanMealId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserDietPlanMeal_Delete",
            [SqlParameterBuilder.Create("@DietPlanMealId", dietPlanMealId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<ActiveDietPlanModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserActiveDietPlan_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, DietPlanRowMapper.MapActiveDietPlan, cancellationToken),
            cancellationToken);

    public Task SetActiveDietPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_UserActiveDietPlan_Set",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@DietPlanId", dietPlanId)],
            cancellationToken);
}
