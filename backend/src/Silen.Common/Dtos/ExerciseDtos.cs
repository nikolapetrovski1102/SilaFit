namespace Silen.Common.Dtos;

/// <summary>An exercise the user couldn't find in the catalogue, added from the
/// exercise picker. Every field is required - they're what the split builder,
/// the suggestion scorer and progress tracking read - so IsCompound is nullable
/// only to tell "not answered" apart from "isolation".</summary>
public sealed class CreateCustomExerciseRequest
{
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string EquipmentType { get; set; } = string.Empty;
    public bool? IsCompound { get; set; }
}
