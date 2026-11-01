namespace Silen.Services.Abstractions;

/// <summary>Turns an uploaded trainer document into the PDF that gets stored, and reads its text for AI import.</summary>
public interface IDocumentProcessor
{
    /// <summary>Returns the upload as PDF bytes: a PDF passes through after a signature check,
    /// a Word file (.doc/.docx) is converted with LibreOffice. Throws
    /// <see cref="Silen.Common.Exceptions.ValidationException"/> for anything else or a failed conversion.</summary>
    Task<byte[]> NormalizeToPdfAsync(byte[] content, string extension, CancellationToken cancellationToken = default);

    /// <summary>The PDF's text in reading order, cut at <paramref name="maxCharacters"/>.
    /// Empty for a scanned document with no text layer.</summary>
    string ExtractText(byte[] pdf, int maxCharacters);
}
