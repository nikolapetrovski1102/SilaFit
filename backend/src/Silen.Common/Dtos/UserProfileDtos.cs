namespace Silen.Common.Dtos;

public sealed class UpsertUserProfileRequest
{
    public string Gender { get; set; } = string.Empty;
    public byte AgeYears { get; set; }
    public decimal HeightCm { get; set; }
    public decimal WeightKg { get; set; }
    public string Goal { get; set; } = string.Empty;
}
