namespace Silen.Common.Models;

public sealed class StreakStatusModel
{
    public int CurrentStreakDays { get; set; }
    public int WeeklyCompliancePercent { get; set; }
}

public sealed class WeekDayStatusModel
{
    public DateTime SessionDate { get; set; }
    public string? SessionStatus { get; set; }
}
