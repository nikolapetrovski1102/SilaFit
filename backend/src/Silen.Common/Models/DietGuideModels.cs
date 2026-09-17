namespace Silen.Common.Models;

/// <summary>A long-form imported diet guide (dbo.DietPlans) - article-style reference
/// reading collected from the public diet-plan catalogue.
///
/// Distinct from <see cref="DietPlanModel"/>, which is the app's day-by-day
/// meal-schedule feature backed by dbo.NutritionPlans. The two share the column name
/// DietPlanId but no other meaning; see schema/045_DietPlans.sql for why.</summary>
public sealed class DietGuideModel
{
    /// <summary>Named DietGuideId rather than the underlying column's DietPlanId so the
    /// API contract does not repeat the dbo.DietPlans naming collision this type exists
    /// to paper over.</summary>
    public Guid DietGuideId { get; set; }

    public string Title { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string? ImageUrl { get; set; }
    public string? SourceUrl { get; set; }
    public string? SourceAuthor { get; set; }
    public int SortOrder { get; set; }

    /// <summary>How many ordered sections this guide has. Populated by the list
    /// procedure so the client can show a length hint without loading the body.</summary>
    public int SectionCount { get; set; }

    /// <summary>The full flattened article body. Only populated by the detail read;
    /// null in list results.</summary>
    public string? ContentText { get; set; }
}

/// <summary>One ordered section of a <see cref="DietGuideModel"/>. Lists and tables from
/// the source article are preserved verbatim as JSON so nothing is lost in flattening.</summary>
public sealed class DietGuideSectionModel
{
    public Guid DietGuideSectionId { get; set; }
    public short SortOrder { get; set; }
    public string? Heading { get; set; }
    public string? BodyText { get; set; }
    public string? ListsJson { get; set; }
    public string? TablesJson { get; set; }
}
