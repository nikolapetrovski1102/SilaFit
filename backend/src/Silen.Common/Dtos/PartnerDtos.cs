using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

/// <summary>Body of every /api/partner call. The user details never travel in the clear,
/// even inside TLS: <see cref="Payload"/> is the JSON of a <see cref="PartnerProvisionPayload"/>
/// or <see cref="PartnerCancelPayload"/>, AES-256-GCM encrypted with the shared partner key
/// (see Silen.Common.Helpers.PartnerPayloadCipher for the exact layout).</summary>
public sealed class PartnerEncryptedRequest
{
    [Required(ErrorMessage = "Payload is required.")]
    [StringLength(8192, ErrorMessage = "Payload is too large.")]
    public string Payload { get; set; } = string.Empty;
}

/// <summary>Decrypted payload of POST /api/partner/leads - a lead that finished sign-up on
/// the partner website and should get a SilaFit account with PRO.</summary>
public sealed class PartnerProvisionPayload
{
    /// <summary>The partner site's own, stable id for this user. Cancel refers to the lead by it.</summary>
    public string? PartnerUserId { get; set; }

    /// <summary>The email the user signed up with - for Apple/Google, the email from their
    /// identity token. The app finds the account by it on the user's first sign-in.</summary>
    public string? Email { get; set; }

    public string? DisplayName { get; set; }

    /// <summary>Apple, Google or Email - how the user signed up on the partner site.</summary>
    public string? Provider { get; set; }

    /// <summary>When the partner built this payload. Must be within
    /// PartnerOptions.MaxPayloadAgeSeconds of the server clock, and not older than the last
    /// request applied to the same lead.</summary>
    public DateTimeOffset? IssuedAtUtc { get; set; }

    /// <summary>Optional answers to the app's onboarding questions, collected on the partner
    /// website. Seeds the account's profile so the app does not ask them again.</summary>
    public PartnerLeadProfile? Profile { get; set; }
}

/// <summary>The app's onboarding answers as the partner sends them. Gender, age, height,
/// weight and goal are required once a profile is sent; the rest are optional, and the app
/// asks for any that are missing. The allowed values are Silen.Services.Helpers.UserProfileRules.</summary>
public sealed class PartnerLeadProfile
{
    public string? Gender { get; set; }

    public int? AgeYears { get; set; }

    public decimal? HeightCm { get; set; }

    public decimal? WeightKg { get; set; }

    public string? Goal { get; set; }

    public int? TrainingDaysPerWeek { get; set; }

    public int? SessionDurationMinutes { get; set; }

    public string? TrainingExperience { get; set; }

    public string? EquipmentAccess { get; set; }

    public string? DailyActivityLevel { get; set; }
}

/// <summary>Decrypted payload of POST /api/partner/leads/cancel - ends the lead's PRO immediately.</summary>
public sealed class PartnerCancelPayload
{
    public string? PartnerUserId { get; set; }

    public DateTimeOffset? IssuedAtUtc { get; set; }
}

/// <summary>What the partner gets back: a <see cref="PartnerLeadResultDto"/> sealed with the
/// shared key under the endpoint's response purpose.</summary>
public sealed class PartnerEncryptedResponse
{
    public string Payload { get; set; } = string.Empty;
}

public sealed class PartnerLeadResultDto
{
    public string PartnerUserId { get; set; } = string.Empty;

    /// <summary>The issuedAtUtc of the request this answers, so the partner can match a
    /// response to its request and reject one replayed from an earlier call.</summary>
    public DateTime RequestIssuedAtUtc { get; set; }

    /// <summary>The SilaFit account behind the lead.</summary>
    public Guid UserId { get; set; }

    /// <summary>Active or Cancelled.</summary>
    public string Status { get; set; } = string.Empty;

    /// <summary>True when this call created the SilaFit account; false when an account with
    /// that email already existed and was used instead.</summary>
    public bool IsNewAccount { get; set; }

    /// <summary>True when the partner PRO grant is in place. False on provision only when the
    /// user already had a live plan of their own, which stays in charge.</summary>
    public bool ProGranted { get; set; }

    /// <summary>True when the provision's profile was saved to the account. False when no
    /// profile was sent, or the account already had onboarding answers, which are kept.</summary>
    public bool ProfileSaved { get; set; }
}
