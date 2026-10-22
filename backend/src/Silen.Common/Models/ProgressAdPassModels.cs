namespace Silen.Common.Models;

/// <summary>The outcome of usp_ProgressAdPass_Grant. Status is Ok or LimitReached; ExpiresAtUtc
/// is the new pass's expiry for Ok, or when the next pass can be granted for LimitReached.</summary>
public sealed class ProgressAdPassGrantModel
{
    public string Status { get; set; } = string.Empty;
    public DateTime? ExpiresAtUtc { get; set; }
}
