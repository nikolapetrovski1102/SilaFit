using Silen.Common.Models;

namespace Silen.Common.Dtos;

public sealed class ActivateSplitRequest
{
    public Guid SplitId { get; set; }
}

public sealed class SplitDetailDto
{
    public WorkoutSplitModel Split { get; set; } = new();
    public List<SplitDayWithExercisesDto> Days { get; set; } = new();
}

public sealed class SplitDayWithExercisesDto
{
    public SplitDayModel Day { get; set; } = new();
    public List<SplitDayExerciseModel> Exercises { get; set; } = new();
}
