using Npgsql;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Maps the outcome row of usp_PartnerLead_Provision / usp_PartnerLead_Cancel.</summary>
public static class PartnerLeadRowMapper
{
    public static PartnerLeadOutcomeModel MapOutcome(NpgsqlDataReader reader) => new()
    {
        Outcome = reader.GetStringValue("Outcome"),
        UserId = reader.GetNullableGuid("UserId"),
        IsNewAccount = reader.GetBoolValue("IsNewAccount"),
        ProGranted = reader.GetBoolValue("ProGranted")
    };
}
