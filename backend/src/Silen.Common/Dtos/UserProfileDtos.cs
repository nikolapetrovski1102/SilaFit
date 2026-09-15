using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

public sealed class UpsertUserProfileRequest
{
    [StringLength(20)]
    public string Gender { get; set; } = string.Empty;

    [Range(1, 120)]
    public byte AgeYears { get; set; }

    [Range(0, 300)]
    public decimal HeightCm { get; set; }

    [Range(0, 500)]
    public decimal WeightKg { get; set; }

    [StringLength(40)]
    public string Goal { get; set; } = string.Empty;
    public int? TrainingDaysPerWeek { get; set; }
    public int? SessionDurationMinutes { get; set; }
    public string? TrainingExperience { get; set; }
    public string? EquipmentAccess { get; set; }
    public string? DailyActivityLevel { get; set; }
}
