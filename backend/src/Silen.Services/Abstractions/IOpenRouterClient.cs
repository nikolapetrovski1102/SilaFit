using System.Text.Json;

namespace Silen.Services.Abstractions;

/// <summary>Thin wrapper over OpenRouter's chat-completions API for structured (JSON-schema) responses.</summary>
public interface IOpenRouterClient
{
    /// <summary>Calls the configured model with strict json_schema structured output and returns the raw JSON
    /// text of the model's response (the caller deserializes it into its own DTO).</summary>
    Task<string> GenerateJsonAsync(
        string systemPrompt, string userPrompt, JsonElement schema, CancellationToken cancellationToken = default);
}
