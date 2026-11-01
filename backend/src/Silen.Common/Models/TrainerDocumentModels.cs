namespace Silen.Common.Models;

/// <summary>A PDF a trainer attached to one of their splits or diet plans (TrainerDocuments.sql).</summary>
public sealed class TrainerDocumentModel
{
    public Guid DocumentId { get; set; }

    /// <summary>"Split" or "DietPlan".</summary>
    public string Kind { get; set; } = string.Empty;

    public Guid? SplitId { get; set; }
    public Guid? DietPlanId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string OriginalFileName { get; set; } = string.Empty;
    public long SizeBytes { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public Guid? OwnerAdminUserId { get; set; }
    public string? OwnerUsername { get; set; }
    public int ActiveGrantCount { get; set; }
}

/// <summary>One document row plus what the service needs to stream it and check ownership.
/// Never serialized to a client: <see cref="StoredFileName"/> is the on-disk name.</summary>
public sealed class TrainerDocumentFileModel
{
    public Guid DocumentId { get; set; }
    public string Kind { get; set; } = string.Empty;
    public Guid? SplitId { get; set; }
    public Guid? DietPlanId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string OriginalFileName { get; set; } = string.Empty;
    public string StoredFileName { get; set; } = string.Empty;
    public long SizeBytes { get; set; }
    public DateTime CreatedAtUtc { get; set; }

    /// <summary>The owner of the split / plan the document is attached to.</summary>
    public Guid? TargetOwnerAdminUserId { get; set; }
}

/// <summary>One client's hand-over of a document - their personal link and how often they opened it.</summary>
public sealed class TrainerDocumentGrantModel
{
    public Guid GrantId { get; set; }
    public Guid DocumentId { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }

    /// <summary>The per-client link token. Opens nothing on its own - see TrainerDocumentService.</summary>
    public string Token { get; set; } = string.Empty;

    public DateTime CreatedAtUtc { get; set; }
    public DateTime? RevokedAtUtc { get; set; }
    public DateTime? LastOpenedAtUtc { get; set; }
    public int OpenCount { get; set; }
    public string? AssignedByUsername { get; set; }

    /// <summary>Set by the service: the link the trainer copies, relative to the API origin.</summary>
    public string ViewerPath { get; set; } = string.Empty;
}

/// <summary>A grant resolved from its link token, with everything the viewer needs to decide
/// whether to render and what to watermark.</summary>
public sealed class TrainerDocumentAccessModel
{
    public Guid GrantId { get; set; }
    public Guid DocumentId { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public DateTime? RevokedAtUtc { get; set; }
    public byte[]? TicketHash { get; set; }
    public DateTime? TicketExpiresAtUtc { get; set; }

    /// <summary>SHA-256 of the link value emailed to the client, and when it stops working.</summary>
    public byte[]? EmailLinkHash { get; set; }
    public DateTime? EmailLinkExpiresAtUtc { get; set; }

    public string Title { get; set; } = string.Empty;
    public string StoredFileName { get; set; } = string.Empty;
    public string Kind { get; set; } = string.Empty;
    public Guid? TargetOwnerAdminUserId { get; set; }
    public string? TrainerUsername { get; set; }
}

/// <summary>A document the signed-in app user holds for one split or diet plan.</summary>
public sealed class UserTrainerDocumentModel
{
    public Guid GrantId { get; set; }
    public Guid DocumentId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Kind { get; set; } = string.Empty;
    public DateTime GrantedAtUtc { get; set; }
    public string? TrainerUsername { get; set; }
}

/// <summary>A partner shop with a discount code (SupplementProviders.sql).</summary>
public sealed class SupplementProviderModel
{
    public Guid ProviderId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public string? LogoUrl { get; set; }
    public string? PromoCode { get; set; }
    public string? DiscountLabel { get; set; }
    public string? ShopUrl { get; set; }

    /// <summary>Protein, Supplements, Food or Gear. The meal tracker nudges toward Protein ones.</summary>
    public string Category { get; set; } = "Protein";

    public int SortOrder { get; set; }
}

/// <summary>The console's view of a provider, including hidden ones.</summary>
public sealed class AdminSupplementProviderModel
{
    public Guid ProviderId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public string? LogoUrl { get; set; }
    public string? PromoCode { get; set; }
    public string? DiscountLabel { get; set; }
    public string? ShopUrl { get; set; }
    public string Category { get; set; } = "Protein";
    public bool IsActive { get; set; }
    public int SortOrder { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}

/// <summary>A meal with what goes into it and how to make it.</summary>
public sealed class MealRecipeModel
{
    public Guid MealSuggestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string MealType { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int CaloriesKcal { get; set; }
    public int ProteinG { get; set; }
    public int CarbsG { get; set; }
    public int FatsG { get; set; }
    public string? ImageUrl { get; set; }
    public string? ServingSuggestion { get; set; }
    public List<string> Ingredients { get; set; } = [];
    public List<string> Steps { get; set; } = [];
}

/// <summary>Ingredients and steps of one meal suggestion as the console edits them.</summary>
public sealed class AdminMealRecipeModel
{
    public Guid MealSuggestionId { get; set; }
    public List<string> Ingredients { get; set; } = [];
    public List<string> Steps { get; set; } = [];
}

/// <summary>Who to tell about a trainer assignment and what to call the program (TrainerDocuments.sql).</summary>
public sealed class TrainerAssignmentNotifyContextModel
{
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public bool NotificationsEnabled { get; set; }
    public string ProgramName { get; set; } = string.Empty;

    /// <summary>The program's owning trainer; null for a catalog program.</summary>
    public string? TrainerUsername { get; set; }
}
