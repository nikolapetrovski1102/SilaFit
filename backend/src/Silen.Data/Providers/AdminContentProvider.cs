using Microsoft.Extensions.Options;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IAdminContentProvider"/>
public sealed class AdminContentProvider(
    ISqlExecutor sqlExecutor,
    IOptions<EncryptionOptions> encryptionOptions) : IAdminContentProvider
{
    private readonly byte[] _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);

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

    public Task<AdminPlanEntitlementsModel?> GetPlanEntitlementsAsync(Guid planId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_PlanEntitlements_GetForPlan",
            [SqlParameterBuilder.Create("@PlanId", planId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AdminContentRowMapper.MapPlanEntitlements, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertPlanEntitlementsAsync(AdminPlanEntitlementsUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_PlanEntitlements_Upsert",
            [
                SqlParameterBuilder.Create("@PlanId", request.PlanId),
                SqlParameterBuilder.Create("@MaxActiveSplits", request.MaxActiveSplits),
                SqlParameterBuilder.Create("@MaxActiveDietPlans", request.MaxActiveDietPlans),
                SqlParameterBuilder.Create("@AllowAiGeneration", request.AllowAiGeneration),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    /* -------------------------------- splits -------------------------------- */

    public Task<List<AdminSplitModel>> GetSplitsAsync(Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Splits_GetAll",
            [
                SqlParameterBuilder.Create("@ViewerAdminUserId", viewerAdminUserId),
                SqlParameterBuilder.Create("@IncludeAll", includeAll)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapSplit, cancellationToken),
            cancellationToken);

    /// <summary>
    /// Three procedures rather than one multi-result-set call: the split list already
    /// carries the counts, and the other two are also used on their own by the day
    /// and prescription editors.
    /// </summary>
    public async Task<AdminSplitDetailModel?> GetSplitDetailAsync(Guid splitId, Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default)
    {
        var splits = await GetSplitsAsync(viewerAdminUserId, includeAll, cancellationToken);
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

    public Task<AdminMutationResultModel> UpsertSplitAsync(AdminSplitUpsertRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
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
                SqlParameterBuilder.Create("@Visibility", request.Visibility),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteSplitAsync(Guid splitId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Split_Delete",
            [
                SqlParameterBuilder.Create("@SplitId", splitId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminSplitAssignmentModel>> GetSplitAssignmentsAsync(Guid splitId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitAssignments_GetForSplit",
            [SqlParameterBuilder.Create("@SplitId", splitId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapSplitAssignment, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> AssignSplitAsync(AdminSplitAssignRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitAssignment_Assign",
            [
                SqlParameterBuilder.Create("@SplitId", request.SplitId),
                SqlParameterBuilder.Create("@UserId", request.UserId),
                SqlParameterBuilder.Create("@SetActive", request.SetActive),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> RemoveSplitAssignmentAsync(Guid splitId, Guid userId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SplitAssignment_Remove",
            [
                SqlParameterBuilder.Create("@SplitId", splitId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
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

    public Task<bool> IsClientAssignedToAsync(Guid adminUserId, Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Client_IsAssignedTo",
            [SqlParameterBuilder.Create("@AdminUserId", adminUserId), SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader, r => r.GetBoolValue("IsAssigned"), cancellationToken),
            cancellationToken);

    public Task<AdminClientOverviewModel?> GetClientOverviewAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync<AdminClientOverviewModel?>(
            "dbo.usp_Admin_Client_GetOverview",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.Date)
            ],
            async reader =>
            {
                if (!await reader.ReadAsync(cancellationToken))
                {
                    return null;
                }

                var model = new AdminClientOverviewModel
                {
                    Account = AdminContentRowMapper.MapUserSummary(reader),
                    Profile = AdminContentRowMapper.MapClientProfile(reader, _key),
                    Targets = AdminContentRowMapper.MapClientTargets(reader, _key),
                    FromDateUtc = fromDateUtc.Date,
                    ToDateUtc = toDateUtc.Date
                };

                if (reader.GetNullableGuid("ActiveSplitId") is { } splitId)
                {
                    model.ActiveSplit = new AdminClientActiveSplitModel
                    {
                        SplitId = splitId,
                        Name = reader.GetNullableString("ActiveSplitName") ?? string.Empty,
                        Category = reader.GetNullableString("ActiveSplitCategory") ?? string.Empty,
                        Level = reader.GetNullableString("ActiveSplitLevel") ?? string.Empty,
                        ActivatedAtUtc = reader.GetNullableDateTime("ActiveSplitActivatedAtUtc") ?? default
                    };
                }

                if (reader.GetNullableGuid("ActiveDietPlanId") is { } dietPlanId)
                {
                    model.ActiveDietPlan = new AdminClientActiveDietPlanModel
                    {
                        DietPlanId = dietPlanId,
                        Name = reader.GetNullableString("ActiveDietPlanName") ?? string.Empty,
                        PeriodType = reader.GetNullableString("ActiveDietPlanPeriodType") ?? string.Empty,
                        ActivatedAtUtc = reader.GetNullableDateTime("ActiveDietPlanActivatedAtUtc") ?? default
                    };
                }

                await reader.NextResultAsync(cancellationToken);
                model.Sessions = await SqlResultSetReader.ReadListAsync(
                    reader, AdminContentRowMapper.MapClientSession, cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                var sets = await SqlResultSetReader.ReadListAsync(
                    reader, AdminContentRowMapper.MapClientSet, cancellationToken);
                var setsBySession = sets.GroupBy(s => s.WorkoutSessionId).ToDictionary(g => g.Key, g => g.ToList());
                foreach (var session in model.Sessions)
                {
                    if (setsBySession.TryGetValue(session.WorkoutSessionId, out var sessionSets))
                    {
                        session.Sets = sessionSets;
                    }
                }

                await reader.NextResultAsync(cancellationToken);
                model.Meals = await SqlResultSetReader.ReadListAsync(
                    reader, r => AdminContentRowMapper.MapClientMeal(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                model.Bodyweight = await SqlResultSetReader.ReadListAsync(
                    reader, r => AdminContentRowMapper.MapClientBodyweight(r, _key), cancellationToken);

                await reader.NextResultAsync(cancellationToken);
                model.Hydration = await SqlResultSetReader.ReadListAsync(
                    reader, AdminContentRowMapper.MapClientHydration, cancellationToken);

                model.Summary = BuildClientSummary(model);
                return model;
            },
            cancellationToken);

    /// <summary>Derives the headline figures in C# because the columns behind
    /// them (meal calories, bodyweight) are ciphertext and can't be aggregated in SQL.</summary>
    private static AdminClientSummaryModel BuildClientSummary(AdminClientOverviewModel model)
    {
        var completed = model.Sessions
            .Where(s => string.Equals(s.Status, "Completed", StringComparison.OrdinalIgnoreCase))
            .ToList();
        var withRpe = completed.Where(s => s.RpeScore is not null).ToList();
        var mealDays = model.Meals
            .GroupBy(m => m.LogDateUtc.Date)
            .Select(g => g.Sum(m => m.CaloriesKcal))
            .ToList();

        return new AdminClientSummaryModel
        {
            CompletedSessions = completed.Count,
            ScheduledSessions = model.Sessions.Count(s =>
                !string.Equals(s.Status, "ActiveRest", StringComparison.OrdinalIgnoreCase)),
            TotalTonnageKg = completed.Sum(s => s.TonnageKg ?? 0m),
            AvgRpe = withRpe.Count == 0 ? 0m : Math.Round(withRpe.Average(s => s.RpeScore!.Value), 1),
            TotalSets = model.Sessions.Sum(s => s.Sets.Count),
            LoggedMeals = model.Meals.Count,
            LoggedMealDays = mealDays.Count,
            TotalDaysInRange = Math.Max(1, (model.ToDateUtc.Date - model.FromDateUtc.Date).Days + 1),
            AvgCaloriesLogged = mealDays.Count == 0 ? null : Math.Round((decimal)mealDays.Average(), 0),
            StartWeightKg = model.Bodyweight.Count == 0 ? null : model.Bodyweight[0].WeightKg,
            EndWeightKg = model.Bodyweight.Count == 0 ? null : model.Bodyweight[^1].WeightKg,
            AvgHydrationMl = model.Hydration.Count == 0
                ? 0
                : (int)Math.Round(model.Hydration.Average(h => h.TotalMl))
        };
    }

    /* ------------------------------- diet plans ------------------------------ */

    public Task<List<AdminDietPlanModel>> GetDietPlansAsync(Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlans_GetAll",
            [
                SqlParameterBuilder.Create("@ViewerAdminUserId", viewerAdminUserId),
                SqlParameterBuilder.Create("@IncludeAll", includeAll)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapDietPlan, cancellationToken),
            cancellationToken);

    /// <summary>
    /// Three procedures rather than one multi-result-set call - same reasoning as
    /// <see cref="GetSplitDetailAsync"/>: the list already carries the counts, and
    /// the other two are also used on their own by the day and meal-slot editors.
    /// </summary>
    public async Task<AdminDietPlanDetailModel?> GetDietPlanDetailAsync(Guid dietPlanId, Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default)
    {
        var plans = await GetDietPlansAsync(viewerAdminUserId, includeAll, cancellationToken);
        var plan = plans.FirstOrDefault(candidate => candidate.DietPlanId == dietPlanId);

        if (plan is null)
        {
            return null;
        }

        return new AdminDietPlanDetailModel
        {
            Plan = plan,
            Days = await GetDietPlanDaysAsync(dietPlanId, cancellationToken),
            Meals = await GetDietPlanMealsAsync(dietPlanId, cancellationToken)
        };
    }

    public Task<AdminMutationResultModel> UpsertDietPlanAsync(AdminDietPlanUpsertRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlan_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanId", request.DietPlanId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Description", request.Description),
                SqlParameterBuilder.Create("@HeroImageUrl", request.HeroImageUrl),
                SqlParameterBuilder.Create("@PeriodType", request.PeriodType),
                SqlParameterBuilder.Create("@DurationDays", request.DurationDays),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                SqlParameterBuilder.Create("@Visibility", request.Visibility),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteDietPlanAsync(Guid dietPlanId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlan_Delete",
            [
                SqlParameterBuilder.Create("@DietPlanId", dietPlanId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminDietPlanAssignmentModel>> GetDietPlanAssignmentsAsync(Guid dietPlanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanAssignments_GetForPlan",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapDietPlanAssignment, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> AssignDietPlanAsync(AdminDietPlanAssignRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanAssignment_Assign",
            [
                SqlParameterBuilder.Create("@DietPlanId", request.DietPlanId),
                SqlParameterBuilder.Create("@UserId", request.UserId),
                SqlParameterBuilder.Create("@SetActive", request.SetActive),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> RemoveDietPlanAssignmentAsync(Guid dietPlanId, Guid userId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanAssignment_Remove",
            [
                SqlParameterBuilder.Create("@DietPlanId", dietPlanId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ActorCanManageAll", canManageAll),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminDietPlanDayModel>> GetDietPlanDaysAsync(Guid dietPlanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanDays_GetForPlan",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapDietPlanDay, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertDietPlanDayAsync(AdminDietPlanDayUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanDay_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanDayId", request.DietPlanDayId),
                SqlParameterBuilder.Create("@DietPlanId", request.DietPlanId),
                SqlParameterBuilder.Create("@DayIndex", request.DayIndex),
                SqlParameterBuilder.Create("@Title", request.Title),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteDietPlanDayAsync(Guid dietPlanDayId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanDay_Delete",
            [SqlParameterBuilder.Create("@DietPlanDayId", dietPlanDayId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminDietPlanMealModel>> GetDietPlanMealsAsync(Guid dietPlanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanMeals_GetForPlan",
            [SqlParameterBuilder.Create("@DietPlanId", dietPlanId)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapDietPlanMeal, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertDietPlanMealAsync(AdminDietPlanMealUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanMeal_Upsert",
            [
                SqlParameterBuilder.Create("@DietPlanMealId", request.DietPlanMealId),
                SqlParameterBuilder.Create("@DietPlanDayId", request.DietPlanDayId),
                SqlParameterBuilder.Create("@MealType", request.MealType),
                SqlParameterBuilder.Create("@MealSuggestionId", request.MealSuggestionId),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteDietPlanMealAsync(Guid dietPlanMealId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_DietPlanMeal_Delete",
            [SqlParameterBuilder.Create("@DietPlanMealId", dietPlanMealId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);
}
