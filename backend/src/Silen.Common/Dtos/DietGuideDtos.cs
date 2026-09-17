using Silen.Common.Models;

namespace Silen.Common.Dtos;

/// <summary>A diet guide plus its ordered sections, for the read-only guide screen.</summary>
public sealed class DietGuideDetailDto
{
    public DietGuideModel Guide { get; set; } = new();
    public List<DietGuideSectionModel> Sections { get; set; } = new();
}
