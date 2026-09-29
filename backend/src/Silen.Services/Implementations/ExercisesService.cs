using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IExercisesService"/>
public sealed class ExercisesService(
    IExercisesProvider exercisesProvider,
    IUserProfileProvider userProfileProvider) : IExercisesService
{
    private const int CloseMatchCount = 6;
    private const int MinNameLength = 2;
    private const int MaxNameLength = 150;

    /// <summary>dbo.Exercises' CK_Exercises_MuscleGroup values.</summary>
    public static readonly IReadOnlyList<string> MuscleGroups = ["chest", "back", "legs", "shoulders", "arms", "core"];

    /// <summary>The catalogue's equipment values, plus Band and Other for kit it
    /// doesn't cover. Kept to a fixed list so ExerciseRecommendationScorer's
    /// equipment checks still read a custom exercise correctly.</summary>
    public static readonly IReadOnlyList<string> EquipmentTypes =
        ["Barbell", "Dumbbell", "Machine", "Cable", "Bodyweight", "Kettlebell", "Band", "Other"];

    public Task<ServiceResult<List<ExerciseModel>>> SearchAsync(
        Guid? userId, string? muscleGroup, string? searchText, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => exercisesProvider.SearchAsync(
            string.IsNullOrWhiteSpace(muscleGroup)
                ? null
                : new[] { muscleGroup.Trim().ToLowerInvariant() },
            searchText,
            userId,
            cancellationToken));

    public Task<ServiceResult<List<ExerciseModel>>> SuggestAsync(
        Guid? userId, IReadOnlyList<string>? muscleGroups, int limit, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // The coarse groups already scope the query set; passing them on to the
            // scorer keeps the requested order when a day names several (e.g.
            // "Chest & Triceps" surfaces chest first, arms after) without letting
            // group intent override equipment/experience fitness.
            // Catalogue only: a user's own exercises are found by searching.
            var exercises = await exercisesProvider.SearchAsync(muscleGroups, null, null, cancellationToken);

            // Profile lookup is best-effort, same as the split scorer: a guest or a
            // user who hasn't finished onboarding still gets a sensible list, just
            // without the equipment/experience personalisation.
            var profile = userId is { } id
                ? await userProfileProvider.GetAsync(id, cancellationToken)
                : null;

            return ExerciseRecommendationScorer.Rank(
                exercises, PersonFit.From(profile), Math.Clamp(limit, 1, 50), muscleGroups);
        });

    public Task<ServiceResult<List<ExerciseModel>>> CloseMatchesAsync(
        Guid userId, string? searchText, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (ExerciseSearchTerms.Parse(searchText).Count == 0)
            {
                return new List<ExerciseModel>();
            }

            var exercises = await exercisesProvider.GetPickableAsync(userId, cancellationToken);
            return ExerciseCloseMatches.Find(exercises, searchText, CloseMatchCount);
        });

    public Task<ServiceResult<ExerciseModel>> CreateCustomAsync(
        Guid userId, CreateCustomExerciseRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() =>
        {
            var name = string.Join(' ', (request.Name ?? string.Empty)
                .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
            if (name.Length < MinNameLength)
            {
                throw new ValidationException("Custom exercise name was blank or too short.", "Give the exercise a name.");
            }

            if (name.Length > MaxNameLength)
            {
                throw new ValidationException("Custom exercise name was too long.", "That name is too long.");
            }

            var muscleGroup = MuscleGroups.FirstOrDefault(group =>
                string.Equals(group, request.MuscleGroup?.Trim(), StringComparison.OrdinalIgnoreCase));
            if (muscleGroup is null)
            {
                throw new ValidationException(
                    $"Custom exercise muscle group '{request.MuscleGroup}' is not a catalogue group.",
                    "Pick the muscle group it trains.");
            }

            var equipment = EquipmentTypes.FirstOrDefault(type =>
                string.Equals(type, request.EquipmentType?.Trim(), StringComparison.OrdinalIgnoreCase));
            if (equipment is null)
            {
                throw new ValidationException(
                    $"Custom exercise equipment '{request.EquipmentType}' is not a known type.",
                    "Pick the equipment it uses.");
            }

            if (request.IsCompound is not { } isCompound)
            {
                throw new ValidationException(
                    "Custom exercise was missing IsCompound.",
                    "Say whether it's a compound or isolation movement.");
            }

            return exercisesProvider.CreateCustomAsync(userId, name, muscleGroup, equipment, isCompound, cancellationToken);
        });
}
