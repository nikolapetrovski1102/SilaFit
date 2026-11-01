namespace Silen.Common.Models;

/// <summary>One motivational line for the app's splash screen.</summary>
public sealed class MotivationalQuoteModel
{
    public Guid QuoteId { get; set; }
    public string Text { get; set; } = string.Empty;
    public string? Author { get; set; }
    public int SortOrder { get; set; }
}
