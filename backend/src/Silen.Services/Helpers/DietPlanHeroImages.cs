namespace Silen.Services.Helpers;

/// <summary>
/// Stable, production-hosted hero artwork for AI-generated weekly diet plans.
/// The user's onboarding goal selects the most representative meal-prep image;
/// unknown or missing goals use the general fitness-meal artwork.
/// </summary>
public static class DietPlanHeroImages
{
    public const string General =
        "https://images.sila.fitness/diet-plans/ai-weekly-general.png";

    public const string BuildMuscle =
        "https://images.sila.fitness/diet-plans/ai-clean-bulk.png";

    public const string LoseFat =
        "https://images.sila.fitness/diet-plans/ai-fat-loss.png";

    public const string MaintainActive =
        "https://images.sila.fitness/diet-plans/ai-healthy-week.png";

    public static string ForGoal(string? goal) => goal switch
    {
        "BuildMuscle" => BuildMuscle,
        "LoseFat" => LoseFat,
        "MaintainActive" => MaintainActive,
        _ => General
    };
}
