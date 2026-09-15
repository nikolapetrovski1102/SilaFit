using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Derived, read-only view of the onboarding profile used to personalize
/// recommendations. Height/weight/age drive the BMI/age bands; the five training
/// answers (days per week, session length, experience, equipment, daily activity)
/// drive the practical-capacity signals. Gender is retained only to match a
/// program's explicit source audience (for example a women-specific program);
/// it does not change level, capacity, or category preferences.
///
/// The training answers are optional so profiles saved before onboarding asked
/// for them still score exactly as they did - every capacity signal is a no-op
/// when its answer is null.
/// </summary>
public sealed record PersonFit(
    double Bmi,
    string BmiCategory,
    string AgeBand,
    string PreferredLevel,
    int? TrainingDaysPerWeek = null,
    int? SessionDurationMinutes = null,
    string? TrainingExperience = null,
    string? EquipmentAccess = null,
    string? DailyActivityLevel = null,
    string? Gender = null)
{
    public const string UnknownCategory = "Unknown";

    /// <summary>Used for guests / users who haven't finished onboarding yet.</summary>
    public static readonly PersonFit Unknown = new(0, UnknownCategory, UnknownCategory, "Beginner");

    public bool HasProfile => BmiCategory != UnknownCategory;

    public static PersonFit From(UserProfileModel? profile)
    {
        if (profile is not { HeightCm: not null, WeightKg: not null, AgeYears: not null })
        {
            return Unknown;
        }

        return From(
            profile.HeightCm.Value,
            profile.WeightKg.Value,
            profile.AgeYears.Value,
            profile.TrainingDaysPerWeek,
            profile.SessionDurationMinutes,
            profile.TrainingExperience,
            profile.EquipmentAccess,
            profile.DailyActivityLevel,
            profile.Gender);
    }

    /// <summary>Height/weight/age only - kept for callers (and tests) that don't
    /// have the training-preference answers.</summary>
    public static PersonFit From(decimal heightCm, decimal weightKg, byte ageYears) =>
        From(heightCm, weightKg, ageYears, null, null, null, null, null);

    public static PersonFit From(
        decimal heightCm,
        decimal weightKg,
        byte ageYears,
        int? trainingDaysPerWeek,
        int? sessionDurationMinutes,
        string? trainingExperience,
        string? equipmentAccess,
        string? dailyActivityLevel,
        string? gender = null)
    {
        var heightM = (double)heightCm / 100.0;
        var bmi = heightM <= 0 ? 0 : (double)weightKg / (heightM * heightM);

        var bmiCategory = bmi switch
        {
            < 18.5 => "Underweight",
            < 25 => "Normal",
            < 30 => "Overweight",
            _ => "Obese"
        };

        var ageBand = ageYears switch
        {
            < 18 => "Teen",
            <= 29 => "Young",
            <= 44 => "Adult",
            _ => "Masters"
        };

        return new PersonFit(
            Math.Round(bmi, 1),
            bmiCategory,
            ageBand,
            PreferredLevelFor(ageBand, bmiCategory, trainingExperience),
            trainingDaysPerWeek,
            sessionDurationMinutes,
            trainingExperience,
            equipmentAccess,
            dailyActivityLevel,
            gender);
    }

    /// <summary>
    /// Self-reported experience is the primary level signal now that onboarding
    /// asks for it, but it is still capped by the age/BMI safety ceiling: a teen,
    /// a master, or an obese profile is never pushed above beginner even if it
    /// claims "Advanced". A healthy adult who answers "Advanced" now gets an
    /// advanced protocol instead of the old age-only "Intermediate" default, and
    /// a missing answer keeps the previous default (Intermediate, or Beginner
    /// under the safety ceiling).
    /// </summary>
    private static string PreferredLevelFor(string ageBand, string bmiCategory, string? experience)
    {
        var ceiling = ageBand is "Teen" or "Masters" || bmiCategory == "Obese" ? BeginnerRank : AdvancedRank;
        var requested = experience switch
        {
            "Beginner" => BeginnerRank,
            "Advanced" => AdvancedRank,
            _ => IntermediateRank
        };

        return Math.Min(requested, ceiling) switch
        {
            BeginnerRank => "Beginner",
            IntermediateRank => "Intermediate",
            _ => "Advanced"
        };
    }

    private const int BeginnerRank = 0;
    private const int IntermediateRank = 1;
    private const int AdvancedRank = 2;
}
