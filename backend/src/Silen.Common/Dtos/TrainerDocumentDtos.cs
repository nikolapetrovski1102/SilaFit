namespace Silen.Common.Dtos;

/// <summary>What happened to an uploaded trainer document: where it was attached and,
/// when AI built the program from it, what was created.</summary>
public sealed class TrainerDocumentUploadResultDto
{
    public Guid DocumentId { get; set; }

    /// <summary>"Split" or "DietPlan".</summary>
    public string Kind { get; set; } = string.Empty;

    /// <summary>The split / plan the document now belongs to - the new one when <see cref="Generated"/>.</summary>
    public Guid TargetId { get; set; }

    /// <summary>True when AI read the document and created a new split / plan from it.</summary>
    public bool Generated { get; set; }

    public string? GeneratedName { get; set; }
    public int GeneratedDays { get; set; }
    public int GeneratedWeeks { get; set; }

    public string Message { get; set; } = string.Empty;
}

/// <summary>Hand a document to one client (or re-issue it after a revoke).</summary>
public sealed class AdminTrainerDocumentGrantRequest
{
    public Guid DocumentId { get; set; }
    public Guid UserId { get; set; }
}

/// <summary>A short-lived link the app opens in its secure viewer.</summary>
public sealed class TrainerDocumentOpenResultDto
{
    public required string ViewerUrl { get; init; }
    public required DateTime ExpiresAtUtc { get; init; }
}

/// <summary>Create (no id) or update a partner shop.</summary>
public sealed class AdminSupplementProviderUpsertRequest
{
    public Guid? ProviderId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public string? LogoUrl { get; set; }
    public string? PromoCode { get; set; }
    public string? DiscountLabel { get; set; }
    public string? ShopUrl { get; set; }
    public string Category { get; set; } = "Protein";
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
}

/// <summary>Replaces a meal suggestion's ingredient and step lists, in order.</summary>
public sealed class AdminMealRecipeRequest
{
    public Guid MealSuggestionId { get; set; }
    public List<string> Ingredients { get; set; } = [];
    public List<string> Steps { get; set; } = [];
}
