using Silen.Common.Models;

namespace Silen.Common.Dtos;

public sealed class UpsertMealLogRequest
{
    public Guid? MealLogId { get; set; }
    public DateOnly LogDateUtc { get; set; }
    public string MealType { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public short CaloriesKcal { get; set; }
    public short ProteinG { get; set; }
    public short CarbsG { get; set; }
    public short FatsG { get; set; }
    public string Status { get; set; } = "Planned";
    public TimeSpan? PlannedLocalTime { get; set; }
}

public sealed class UpsertNutritionTargetsRequest
{
    public short TargetCalories { get; set; }
    public short TargetProteinG { get; set; }
    public short TargetCarbsG { get; set; }
    public short TargetFatsG { get; set; }
}

/// <summary>Composed view the app renders for one day: targets, the day's meals, and derived totals.</summary>
public sealed class MealDayDto
{
    public UserNutritionTargetsModel Targets { get; set; } = new();
    public List<MealLogModel> Meals { get; set; } = [];
    public int ConsumedCalories { get; set; }
    public int RemainingCalories { get; set; }
    public int ConsumedProteinG { get; set; }
    public int ConsumedCarbsG { get; set; }
    public int ConsumedFatsG { get; set; }
}
