namespace Silen.Common.Options;

/// <summary>Tunables for the monthly review batch (see Silen.Tools.MonthlyReview).</summary>
public sealed class MonthlyReviewOptions
{
    public const string SectionName = "MonthlyReview";

    /// <summary>Plan code whose active subscribers get a report. Defaults to the ADVANCED tier.</summary>
    public string PlanCode { get; set; } = "ADVANCED";

    /// <summary>
    /// When false (or when Smtp:Host is unconfigured) the batch still generates and
    /// stores every report but skips the email - useful for a dry run / manual backfill.
    /// </summary>
    public bool SendEmails { get; set; } = true;

    /// <summary>
    /// When true the batch also emails non-paying users a stats teaser with an
    /// upgrade CTA (no AI generation, so it costs nothing per user and does not
    /// give away the paid report). Same dry-run / SMTP gating as <see cref="SendEmails"/>.
    /// </summary>
    public bool SendUpsellEmails { get; set; } = true;

    /// <summary>
    /// Label stored in MonthlyReviewRuns.PlanCode for the non-paying pass. Purely
    /// for audit/reporting - non-paying users have no real subscription row.
    /// </summary>
    public string UpsellAudienceCode { get; set; } = "FREE";

    /// <summary>
    /// A non-paying user only gets a teaser when the month has at least this many
    /// tracked units (completed sessions + days with a meal logged) - otherwise
    /// there is nothing real to show and the mail would read as spam.
    /// </summary>
    public int UpsellMinTrackedUnits { get; set; } = 1;

    /// <summary>Where the "unlock your review" call to action points.</summary>
    public string UpgradeUrl { get; set; } = "https://sila.fitness/#pricing";
}
