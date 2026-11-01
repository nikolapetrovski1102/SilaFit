using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Exceptions;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IDocumentProcessor"/>
public sealed class DocumentProcessor(IOptions<TrainerDocumentOptions> options, ILogger<DocumentProcessor> logger) : IDocumentProcessor
{
    private static readonly byte[] PdfSignature = "%PDF-"u8.ToArray();

    public async Task<byte[]> NormalizeToPdfAsync(byte[] content, string extension, CancellationToken cancellationToken = default)
    {
        switch (extension.ToLowerInvariant())
        {
            case ".pdf":
                if (!StartsWithPdfSignature(content))
                {
                    throw new ValidationException("Upload named .pdf has no PDF signature.", "That file isn't a valid PDF.");
                }
                return content;

            case ".docx":
            case ".doc":
                var pdf = await ConvertWithLibreOfficeAsync(content, extension.ToLowerInvariant(), cancellationToken);
                if (!StartsWithPdfSignature(pdf))
                {
                    throw new ValidationException("LibreOffice produced output without a PDF signature.",
                        "That Word document couldn't be converted. Export it as PDF and upload that instead.");
                }
                return pdf;

            default:
                throw new ValidationException($"Document upload rejected for extension '{extension}'.",
                    "Only PDF and Word (.docx, .doc) documents are accepted.");
        }
    }

    public string ExtractText(byte[] pdf, int maxCharacters)
    {
        try
        {
            using var document = PdfDocument.Open(pdf);
            var text = new StringBuilder();
            foreach (var page in document.GetPages())
            {
                text.AppendLine(ContentOrderTextExtractor.GetText(page));
                text.AppendLine();
                if (text.Length >= maxCharacters)
                {
                    break;
                }
            }

            var result = text.ToString().Trim();
            return result.Length > maxCharacters ? result[..maxCharacters] : result;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            throw new ValidationException($"PDF text extraction failed: {exception.GetType().Name}.",
                "That document couldn't be read. If it's password-protected, remove the password and upload it again.");
        }
    }

    private static bool StartsWithPdfSignature(byte[] content)
    {
        // The spec allows a little junk before the header; real files from Word,
        // Pages and Google Docs put it at byte 0, but scanners sometimes don't.
        var window = Math.Min(content.Length, 1024);
        return content.AsSpan(0, window).IndexOf(PdfSignature) >= 0;
    }

    private async Task<byte[]> ConvertWithLibreOfficeAsync(byte[] content, string extension, CancellationToken cancellationToken)
    {
        var settings = options.Value;
        var workDir = Path.Combine(Path.GetTempPath(), "silen-convert-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workDir);

        try
        {
            var inputPath = Path.Combine(workDir, "document" + extension);
            await File.WriteAllBytesAsync(inputPath, content, cancellationToken);

            var startInfo = new ProcessStartInfo
            {
                FileName = settings.SofficePath,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add("--headless");
            startInfo.ArgumentList.Add("--norestore");
            startInfo.ArgumentList.Add("--nolockcheck");
            // A private profile per run: the API user has no writable home in the
            // container, and two conversions sharing a profile block each other.
            startInfo.ArgumentList.Add("-env:UserInstallation=file://" + Path.Combine(workDir, "profile"));
            startInfo.ArgumentList.Add("--convert-to");
            startInfo.ArgumentList.Add("pdf");
            startInfo.ArgumentList.Add("--outdir");
            startInfo.ArgumentList.Add(workDir);
            startInfo.ArgumentList.Add(inputPath);

            using var process = new Process { StartInfo = startInfo };
            try
            {
                process.Start();
            }
            catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException)
            {
                throw new ConflictException($"LibreOffice ('{settings.SofficePath}') could not be started: {exception.Message}",
                    "Word conversion isn't available right now. Export the document as PDF and upload that instead.");
            }

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(settings.ConversionTimeoutSeconds));
            var stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                process.Kill(entireProcessTree: true);
                throw new ValidationException("LibreOffice conversion timed out.",
                    "That Word document took too long to convert. Export it as PDF and upload that instead.");
            }

            var outputPath = Path.Combine(workDir, "document.pdf");
            if (process.ExitCode != 0 || !File.Exists(outputPath))
            {
                logger.LogWarning("LibreOffice exited with {ExitCode}: {StdErr}", process.ExitCode, (await stderr).Trim());
                _ = await stdout;
                throw new ValidationException($"LibreOffice exited with code {process.ExitCode}.",
                    "That Word document couldn't be converted. Export it as PDF and upload that instead.");
            }

            return await File.ReadAllBytesAsync(outputPath, cancellationToken);
        }
        finally
        {
            try
            {
                Directory.Delete(workDir, recursive: true);
            }
            catch (IOException)
            {
                // Temp cleanup is best effort; the OS reclaims the temp dir eventually.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}
