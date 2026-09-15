using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IProgressService"/>
public sealed class ProgressService(
    IWorkoutSessionProvider workoutSessionProvider,
    IStreakProvider streakProvider) : IProgressService
{
    public Task<ServiceResult<ProgressOverviewDto>> GetOverviewAsync(Guid userId, int days, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var effectiveDays = days <= 0 ? 30 : days;
            var toDate = DateTime.UtcNow.Date;
            var fromDate = toDate.AddDays(-(effectiveDays - 1));

            var (summary, dayStatuses) = await workoutSessionProvider.GetRangeSummaryAsync(userId, fromDate, toDate, cancellationToken);
            var (streakStatus, _) = await streakProvider.GetStatusAsync(userId, cancellationToken);

            return new ProgressOverviewDto
            {
                CurrentStreakDays = streakStatus.CurrentStreakDays,
                WeeklyCompliancePercent = streakStatus.WeeklyCompliancePercent,
                CompletedSessions = summary.CompletedSessions,
                ScheduledSessions = summary.ScheduledSessions,
                TotalTonnageKg = summary.TotalTonnageKg,
                AvgRpe = summary.AvgRpe,
                Heatmap = dayStatuses.Select(d => new HeatmapDayDto
                {
                    Date = d.ScheduledDateUtc,
                    Status = d.Status,
                    TonnageKg = d.TonnageKg,
                    RpeScore = d.RpeScore
                }).ToList(),
                Insights = ProgressInsightGenerator.Generate(summary, streakStatus)
            };
        });

    public Task<ServiceResult<List<PersonalRecordDto>>> GetPersonalRecordsAsync(Guid userId, int top, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var effectiveTop = top <= 0 ? 5 : top;
            var records = await workoutSessionProvider.GetPersonalRecordsAsync(userId, effectiveTop, cancellationToken);

            return records.Select(r => new PersonalRecordDto
            {
                ExerciseId = r.ExerciseId,
                ExerciseName = r.ExerciseName,
                WeightKg = r.WeightKg,
                Reps = r.Reps,
                AchievedAtUtc = r.AchievedAtUtc,
                PreviousBestWeightKg = r.PreviousBestWeightKg
            }).ToList();
        });
}
