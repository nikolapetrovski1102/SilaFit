namespace Silen.Common.Options;

/// <summary>
/// Bound from the "TrainerDocuments" configuration section. Trainer PDFs are kept in
/// <see cref="StoragePath"/>, which must NOT be the public uploads directory: the
/// files are only ever streamed through the API after the caller proves they may
/// read them (an admin session or a short-lived app ticket).
/// </summary>
public sealed class TrainerDocumentOptions
{
    public const string SectionName = "TrainerDocuments";

    /// <summary>Private directory for stored PDFs. Relative paths resolve against the API's working directory.</summary>
    public string StoragePath { get; set; } = "trainer-documents";

    /// <summary>Origin the app's viewer links are built on, e.g. "https://api.sila.fitness". No trailing slash.</summary>
    public string PublicBaseUrl { get; set; } = "http://localhost:5010";

    public long MaxFileSizeBytes { get; set; } = 20 * 1024 * 1024;

    /// <summary>LibreOffice binary used to turn .doc/.docx uploads into PDF.</summary>
    public string SofficePath { get; set; } = "soffice";

    public int ConversionTimeoutSeconds { get; set; } = 90;

    /// <summary>How long a ticket the app mints stays usable. Short on purpose: the
    /// link that carries it is useless to anyone it gets forwarded to soon after.</summary>
    public int TicketLifetimeMinutes { get; set; } = 10;

    /// <summary>How long the link in a client's "your trainer shared a program" email keeps
    /// opening the PDF. Each new email replaces the previous link; revoking the grant kills it.</summary>
    public int EmailLinkLifetimeHours { get; set; } = 72;

    /// <summary>Push + email the client when a trainer assigns them a split / diet plan or
    /// shares a document. Off sends nothing (the assignment itself is unaffected).</summary>
    public bool NotifyClientsOnAssign { get; set; } = true;

    /// <summary>Model for turning a document into a program. Blank falls back to OpenRouter:Model.</summary>
    public string? ImportModel { get; set; }

    /// <summary>Output budget for an import. A 26-week program is a long JSON answer.</summary>
    public int ImportMaxTokens { get; set; } = 32000;

    /// <summary>Document text beyond this many characters is cut before it is sent to the model.</summary>
    public int MaxPromptCharacters { get; set; } = 60000;
}
