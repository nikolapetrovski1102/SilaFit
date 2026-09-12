namespace Silen.Common.Models;

public sealed class UserProfileModel
{
    public Guid UserId { get; set; }
    public string? Gender { get; set; }
    public byte? AgeYears { get; set; }
    public decimal? HeightCm { get; set; }
    public decimal? WeightKg { get; set; }
    public string? Goal { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}
