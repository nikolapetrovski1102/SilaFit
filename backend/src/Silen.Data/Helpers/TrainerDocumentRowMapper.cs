using Npgsql;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Row mappers for TrainerDocuments.sql, SupplementProviders.sql and the recipe reads.</summary>
public static class TrainerDocumentRowMapper
{
    public static TrainerDocumentModel MapDocument(NpgsqlDataReader reader) => new()
    {
        DocumentId = reader.GetGuidValue("DocumentId"),
        Kind = reader.GetStringValue("Kind"),
        SplitId = reader.GetNullableGuid("SplitId"),
        DietPlanId = reader.GetNullableGuid("DietPlanId"),
        Title = reader.GetStringValue("Title"),
        OriginalFileName = reader.GetStringValue("OriginalFileName"),
        SizeBytes = Convert.ToInt64(reader.GetValue(reader.GetOrdinal("SizeBytes"))),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        OwnerAdminUserId = reader.GetNullableGuid("OwnerAdminUserId"),
        OwnerUsername = reader.GetNullableString("OwnerUsername"),
        ActiveGrantCount = reader.GetInt32Value("ActiveGrantCount")
    };

    public static TrainerDocumentFileModel MapDocumentFile(NpgsqlDataReader reader) => new()
    {
        DocumentId = reader.GetGuidValue("DocumentId"),
        Kind = reader.GetStringValue("Kind"),
        SplitId = reader.GetNullableGuid("SplitId"),
        DietPlanId = reader.GetNullableGuid("DietPlanId"),
        Title = reader.GetStringValue("Title"),
        OriginalFileName = reader.GetStringValue("OriginalFileName"),
        StoredFileName = reader.GetStringValue("StoredFileName"),
        SizeBytes = Convert.ToInt64(reader.GetValue(reader.GetOrdinal("SizeBytes"))),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        TargetOwnerAdminUserId = reader.GetNullableGuid("TargetOwnerAdminUserId")
    };

    public static TrainerDocumentGrantModel MapGrant(NpgsqlDataReader reader) => new()
    {
        GrantId = reader.GetGuidValue("GrantId"),
        DocumentId = reader.GetGuidValue("DocumentId"),
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        Token = reader.GetStringValue("Token"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        RevokedAtUtc = reader.GetNullableDateTime("RevokedAtUtc"),
        LastOpenedAtUtc = reader.GetNullableDateTime("LastOpenedAtUtc"),
        OpenCount = reader.GetInt32Value("OpenCount"),
        AssignedByUsername = reader.GetNullableString("AssignedByUsername")
    };

    public static TrainerDocumentAccessModel MapAccess(NpgsqlDataReader reader) => new()
    {
        GrantId = reader.GetGuidValue("GrantId"),
        DocumentId = reader.GetGuidValue("DocumentId"),
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        RevokedAtUtc = reader.GetNullableDateTime("RevokedAtUtc"),
        TicketHash = reader.GetNullableBytes("TicketHash"),
        TicketExpiresAtUtc = reader.GetNullableDateTime("TicketExpiresAtUtc"),
        EmailLinkHash = reader.GetNullableBytes("EmailLinkHash"),
        EmailLinkExpiresAtUtc = reader.GetNullableDateTime("EmailLinkExpiresAtUtc"),
        Title = reader.GetStringValue("Title"),
        StoredFileName = reader.GetStringValue("StoredFileName"),
        Kind = reader.GetStringValue("Kind"),
        TargetOwnerAdminUserId = reader.GetNullableGuid("TargetOwnerAdminUserId"),
        TrainerUsername = reader.GetNullableString("TrainerUsername")
    };

    public static UserTrainerDocumentModel MapUserDocument(NpgsqlDataReader reader) => new()
    {
        GrantId = reader.GetGuidValue("GrantId"),
        DocumentId = reader.GetGuidValue("DocumentId"),
        Title = reader.GetStringValue("Title"),
        Kind = reader.GetStringValue("Kind"),
        GrantedAtUtc = reader.GetDateTimeValue("GrantedAtUtc"),
        TrainerUsername = reader.GetNullableString("TrainerUsername")
    };

    public static string MapToken(NpgsqlDataReader reader) => reader.GetStringValue("Token");

    public static TrainerAssignmentNotifyContextModel MapNotifyContext(NpgsqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        NotificationsEnabled = reader.GetBoolValue("NotificationsEnabled"),
        ProgramName = reader.GetStringValue("ProgramName"),
        TrainerUsername = reader.GetNullableString("TrainerUsername")
    };

    public static SupplementProviderModel MapProvider(NpgsqlDataReader reader) => new()
    {
        ProviderId = reader.GetGuidValue("ProviderId"),
        Name = reader.GetStringValue("Name"),
        Tagline = reader.GetNullableString("Tagline"),
        LogoUrl = reader.GetNullableString("LogoUrl"),
        PromoCode = reader.GetNullableString("PromoCode"),
        DiscountLabel = reader.GetNullableString("DiscountLabel"),
        ShopUrl = reader.GetNullableString("ShopUrl"),
        Category = reader.GetStringValue("Category"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };

    public static AdminSupplementProviderModel MapAdminProvider(NpgsqlDataReader reader) => new()
    {
        ProviderId = reader.GetGuidValue("ProviderId"),
        Name = reader.GetStringValue("Name"),
        Tagline = reader.GetNullableString("Tagline"),
        LogoUrl = reader.GetNullableString("LogoUrl"),
        PromoCode = reader.GetNullableString("PromoCode"),
        DiscountLabel = reader.GetNullableString("DiscountLabel"),
        ShopUrl = reader.GetNullableString("ShopUrl"),
        Category = reader.GetStringValue("Category"),
        IsActive = reader.GetBoolValue("IsActive"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };

    public static MealRecipeModel MapRecipeHeader(NpgsqlDataReader reader) => new()
    {
        MealSuggestionId = reader.GetGuidValue("MealSuggestionId"),
        Title = reader.GetStringValue("Title"),
        MealType = reader.GetStringValue("MealType"),
        Description = reader.GetNullableString("Description"),
        CaloriesKcal = reader.GetInt32Value("CaloriesKcal"),
        ProteinG = reader.GetInt32Value("ProteinG"),
        CarbsG = reader.GetInt32Value("CarbsG"),
        FatsG = reader.GetInt32Value("FatsG"),
        ImageUrl = reader.GetNullableString("ImageUrl"),
        ServingSuggestion = reader.GetNullableString("ServingSuggestion")
    };

    public static string MapIngredientText(NpgsqlDataReader reader) => reader.GetStringValue("IngredientText");

    public static string MapInstructionText(NpgsqlDataReader reader) => reader.GetStringValue("InstructionText");

    /// <summary>Reads the recipe procedure's three result sets: header, ingredients, steps.
    /// Null when the header set is empty (unknown meal or someone else's custom one).</summary>
    public static async Task<MealRecipeModel?> ReadRecipeAsync(NpgsqlDataReader reader, CancellationToken cancellationToken)
    {
        var recipe = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, MapRecipeHeader, cancellationToken);
        if (recipe is null)
        {
            return null;
        }

        await reader.NextResultAsync(cancellationToken);
        recipe.Ingredients = await SqlResultSetReader.ReadListAsync(reader, MapIngredientText, cancellationToken);
        await reader.NextResultAsync(cancellationToken);
        recipe.Steps = await SqlResultSetReader.ReadListAsync(reader, MapInstructionText, cancellationToken);
        return recipe;
    }

    /// <summary>Reads the console recipe procedure's two result sets: ingredients, then steps.</summary>
    public static async Task<AdminMealRecipeModel> ReadAdminRecipeAsync(
        NpgsqlDataReader reader, Guid mealSuggestionId, CancellationToken cancellationToken)
    {
        var recipe = new AdminMealRecipeModel { MealSuggestionId = mealSuggestionId };
        recipe.Ingredients = await SqlResultSetReader.ReadListAsync(reader, MapIngredientText, cancellationToken);
        await reader.NextResultAsync(cancellationToken);
        recipe.Steps = await SqlResultSetReader.ReadListAsync(reader, MapInstructionText, cancellationToken);
        return recipe;
    }
}
