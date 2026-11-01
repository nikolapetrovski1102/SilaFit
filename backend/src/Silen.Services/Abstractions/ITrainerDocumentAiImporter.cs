using Silen.Services.Helpers;

namespace Silen.Services.Abstractions;

/// <summary>Reads a trainer's document text with AI and returns the split or diet plan it describes.</summary>
public interface ITrainerDocumentAiImporter
{
    Task<ImportedProgram> ReadSplitAsync(string documentText, string? titleHint, CancellationToken cancellationToken = default);

    Task<ImportedProgram> ReadDietPlanAsync(string documentText, string? titleHint, CancellationToken cancellationToken = default);
}
