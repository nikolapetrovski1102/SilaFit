using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Read-only access to the imported long-form diet guides
/// (dbo.DietPlans / dbo.DietPlanSections). Deliberately separate from
/// <see cref="IDietPlansProvider"/>, which serves the app's day-by-day
/// meal-schedule feature backed by dbo.NutritionPlans.</summary>
public interface IDietGuidesProvider
{
    /// <summary>Every shipped guide, ordered, with its section count. No visibility
    /// filter: these are reference articles rather than assignable plans.</summary>
    Task<List<DietGuideModel>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>The guide header (or null when the id is unknown) plus its ordered sections.</summary>
    Task<(DietGuideModel? Guide, List<DietGuideSectionModel> Sections)> GetDetailAsync(
        Guid dietGuideId, CancellationToken cancellationToken = default);
}
