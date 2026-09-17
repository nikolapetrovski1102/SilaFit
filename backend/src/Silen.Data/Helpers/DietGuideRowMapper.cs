using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Imported long-form diet guide rows (DietGuides.sql).</summary>
public static class DietGuideRowMapper
{
    /// <summary>List projection: header fields plus the section count.</summary>
    public static DietGuideModel MapGuide(SqlDataReader reader) => new()
    {
        DietGuideId = reader.GetGuidValue("DietPlanId"),
        Title = reader.GetStringValue("Title"),
        Summary = reader.GetNullableString("Summary"),
        ImageUrl = reader.GetNullableString("ImageUrl"),
        SourceUrl = reader.GetNullableString("SourceUrl"),
        SourceAuthor = reader.GetNullableString("SourceAuthor"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        SectionCount = reader.GetInt32Value("SectionCount")
    };

    /// <summary>Detail projection: the same header plus the flattened ContentText.
    /// SectionCount is not selected here, so it stays 0.</summary>
    public static DietGuideModel MapGuideDetail(SqlDataReader reader) => new()
    {
        DietGuideId = reader.GetGuidValue("DietPlanId"),
        Title = reader.GetStringValue("Title"),
        Summary = reader.GetNullableString("Summary"),
        ContentText = reader.GetNullableString("ContentText"),
        ImageUrl = reader.GetNullableString("ImageUrl"),
        SourceUrl = reader.GetNullableString("SourceUrl"),
        SourceAuthor = reader.GetNullableString("SourceAuthor"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };

    public static DietGuideSectionModel MapSection(SqlDataReader reader) => new()
    {
        DietGuideSectionId = reader.GetGuidValue("DietPlanSectionId"),
        SortOrder = reader.GetInt16Value("SortOrder"),
        Heading = reader.GetNullableString("Heading"),
        BodyText = reader.GetNullableString("BodyText"),
        ListsJson = reader.GetNullableString("ListsJson"),
        TablesJson = reader.GetNullableString("TablesJson")
    };
}
