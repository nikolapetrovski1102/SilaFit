namespace Silen.Common.Models;

/// <summary>The outcome row of usp_PartnerLead_Provision / usp_PartnerLead_Cancel. Outcome is
/// Ok, Stale, EmailTaken, AccountDisabled (provision) or NotFound (cancel).</summary>
public sealed class PartnerLeadOutcomeModel
{
    public string Outcome { get; set; } = string.Empty;
    public Guid? UserId { get; set; }
    public bool IsNewAccount { get; set; }
    public bool ProGranted { get; set; }
}
