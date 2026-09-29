namespace Silen.Common.Options;

/// <summary>Bound from the "Support" configuration section - where the website's
/// support contact form delivers messages (see SupportService).</summary>
public sealed class SupportOptions
{
    public const string SectionName = "Support";

    public string InboxAddress { get; set; } = "support@sila.fitness";
}
