namespace Silen.Common.Models;

public sealed class BodyweightEntryModel
{
    public Guid BodyweightLogId { get; set; }
    public decimal WeightKg { get; set; }
    public DateTime LoggedAtUtc { get; set; }
}
