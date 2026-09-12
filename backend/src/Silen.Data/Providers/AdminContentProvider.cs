using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IAdminContentProvider"/>
public sealed class AdminContentProvider(ISqlExecutor sqlExecutor) : IAdminContentProvider
{
    /* ------------------------------- exercises ------------------------------ */

    public Task<List<AdminExerciseModel>> GetExercisesAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Exercises_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapExercise, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertExerciseAsync(AdminExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Exercise_Upsert",
            [
                SqlParameterBuilder.Create("@ExerciseId", request.ExerciseId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@MuscleGroup", request.MuscleGroup),
                SqlParameterBuilder.Create("@EquipmentType", request.EquipmentType),
                SqlParameterBuilder.Create("@IsCompound", request.IsCompound),
                SqlParameterBuilder.Create("@DemoVideoUrl", request.DemoVideoUrl),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteExerciseAsync(Guid exerciseId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Exercise_Delete",
            [SqlParameterBuilder.Create("@ExerciseId", exerciseId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    /* --------------------------- meal suggestions ---------------------------- */

    public Task<List<AdminMealSuggestionModel>> GetMealSuggestionsAsync(
        int? suggestedMonth,
        string? mealType,
        string? search,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_MealSuggestions_GetAll",
            [
                SqlParameterBuilder.Create("@SuggestedMonth", suggestedMonth),
                SqlParameterBuilder.Create("@MealType", mealType),
                SqlParameterBuilder.Create("@Search", search)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapMealSuggestion, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertMealSuggestionAsync(AdminMealSuggestionUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_MealSuggestion_Upsert",
            [
                SqlParameterBuilder.Create("@MealSuggestionId", request.MealSuggestionId),
                SqlParameterBuilder.Create("@Title", request.Title),
                SqlParameterBuilder.Create("@MealType", request.MealType),
                SqlParameterBuilder.Create("@Description", request.Description),
                SqlParameterBuilder.Create("@CaloriesKcal", request.CaloriesKcal),
                SqlParameterBuilder.Create("@ProteinG", request.ProteinG),
                SqlParameterBuilder.Create("@CarbsG", request.CarbsG),
                SqlParameterBuilder.Create("@FatsG", request.FatsG),
                SqlParameterBuilder.Create("@SuggestedMonth", request.SuggestedMonth),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteMealSuggestionAsync(Guid mealSuggestionId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_MealSuggestion_Delete",
            [SqlParameterBuilder.Create("@MealSuggestionId", mealSuggestionId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    /* --------------------------------- plans -------------------------------- */

    public Task<List<AdminPlanModel>> GetPlansAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Plans_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapPlan, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertPlanAsync(AdminPlanUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Plan_Upsert",
            [
                SqlParameterBuilder.Create("@PlanId", request.PlanId),
                SqlParameterBuilder.Create("@Code", request.Code),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Tagline", request.Tagline),
                SqlParameterBuilder.Create("@MonthlyPrice", request.MonthlyPrice),
                SqlParameterBuilder.Create("@YearlyPrice", request.YearlyPrice),
                SqlParameterBuilder.Create("@IsFeatured", request.IsFeatured),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeletePlanAsync(Guid planId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Plan_Delete",
            [SqlParameterBuilder.Create("@PlanId", planId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminPlanFeatureModel>> GetPlanFeaturesAsync(Guid planId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_PlanFeatures_GetForPlan",
            [SqlParameterBuilder.Create("@PlanId", planId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapPlanFeature, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertPlanFeatureAsync(AdminPlanFeatureUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_PlanFeature_Upsert",
            [
                SqlParameterBuilder.Create("@PlanFeatureId", request.PlanFeatureId),
                SqlParameterBuilder.Create("@PlanId", request.PlanId),
                SqlParameterBuilder.Create("@FeatureText", request.FeatureText),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                SqlParameterBuilder.Create("@IsHighlighted", request.IsHighlighted),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeletePlanFeatureAsync(Guid planFeatureId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_PlanFeature_Delete",
            [SqlParameterBuilder.Create("@PlanFeatureId", planFeatureId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    /* -------------------------------- splits -------------------------------- */

    public Task<List<AdminSplitModel>> GetSplitsAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Splits_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapSplit, cancellationToken),
            cancellationToken);

    /// <summary>
    /// Three procedures rather than one multi-result-set call: the split list already
    /// carries the counts, and the other two are also used on their own by the day
    /// and prescription editors.
    /// </summary>
    public async Task<AdminSplitDetailModel?> GetSplitDetailAsync(Guid splitId, CancellationToken cancellationToken = default)
    {
        var splits = await GetSplitsAsync(cancellationToken);
        var split = splits.FirstOrDefault(candidate => candidate.SplitId == splitId);

        if (split is null)
        {
            return null;
        }

        return new AdminSplitDetailModel
        {
            Split = split,
            Days = await GetSplitDaysAsync(splitId, cancellationToken),
            DayExercises = await GetSplitDayExercisesAsync(splitId, cancellationToken)
        };
    }

    public Task<AdminMutationResultModel> UpsertSplitAsync(AdminSplitUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Split_Upsert",
            [
                SqlParameterBuilder.Create("@SplitId", request.SplitId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Category", request.Category),
                SqlParameterBuilder.Create("@Level", request.Level),
                SqlParameterBuilder.Create("@DurationDays", request.DurationDays),
                SqlParameterBuilder.Create("@Description", request.Description),
                SqlParameterBuilder.Create("@HeroImageUrl", request.HeroImageUrl),
                SqlParameterBuilder.Create("@RecommendedGoal", request.RecommendedGoal),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteSplitAsync(Guid splitId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Split_Delete",
            [SqlParameterBuilder.Create("@SplitId", splitId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminSplitDayModel>> GetSplitDaysAsync(Guid splitId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDays_GetForSplit",
            [SqlParameterBuilder.Create("@SplitId", splitId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapSplitDay, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertSplitDayAsync(AdminSplitDayUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDay_Upsert",
            [
                SqlParameterBuilder.Create("@SplitDayId", request.SplitDayId),
                SqlParameterBuilder.Create("@SplitId", request.SplitId),
                SqlParameterBuilder.Create("@DayIndex", request.DayIndex),
                SqlParameterBuilder.Create("@Title", request.Title),
                SqlParameterBuilder.Create("@FocusLabel", request.FocusLabel),
                SqlParameterBuilder.Create("@EstimatedMinutes", request.EstimatedMinutes),
                SqlParameterBuilder.Create("@IsRestDay", request.IsRestDay),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteSplitDayAsync(Guid splitDayId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDay_Delete",
            [SqlParameterBuilder.Create("@SplitDayId", splitDayId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminSplitDayExerciseModel>> GetSplitDayExercisesAsync(Guid splitId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDayExercises_GetForSplit",
            [SqlParameterBuilder.Create("@SplitId", splitId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapSplitDayExercise, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertSplitDayExerciseAsync(AdminSplitDayExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDayExercise_Upsert",
            [
                SqlParameterBuilder.Create("@SplitDayExerciseId", request.SplitDayExerciseId),
                SqlParameterBuilder.Create("@SplitDayId", request.SplitDayId),
                SqlParameterBuilder.Create("@ExerciseId", request.ExerciseId),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                SqlParameterBuilder.Create("@TargetSets", request.TargetSets),
                SqlParameterBuilder.Create("@TargetRepsLow", request.TargetRepsLow),
                SqlParameterBuilder.Create("@TargetRepsHigh", request.TargetRepsHigh),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteSplitDayExerciseAsync(Guid splitDayExerciseId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitDayExercise_Delete",
            [SqlParameterBuilder.Create("@SplitDayExerciseId", splitDayExerciseId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    /* --------------------------------- users -------------------------------- */

    public Task<List<AdminUserSummaryModel>> GetUsersAsync(string? search, int limit, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Users_GetAll",
            [SqlParameterBuilder.Create("@Search", search), SqlParameterBuilder.Create("@Limit", limit)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapUserSummary, cancellationToken),
            cancellationToken);
}
