using System.Text.Json;

namespace Silen.Services.Abstractions;

/// <summary>Thin wrapper over OpenRouter's chat-completions API for structured (JSON-schema) responses.</summary>
public interface IOpenRouterClient
{
    /// <summary>Calls OpenRouter with strict json_schema structured output and returns the raw JSON
    /// text of the model's response (the caller deserializes it into its own DTO). <paramref name="model"/>
    /// overrides the globally configured model for this call - callers pass the model the prompt template
    /// was tuned for, so a global override (e.g. a free/experimental model in a deployment's .env) can't
    /// silently break structured output; it falls back to <c>OpenRouter:Model</c> when null/blank.</summary>
    Task<string> GenerateJsonAsync(
        string systemPrompt, string userPrompt, JsonElement schema, string? model = null,
        CancellationToken cancellationToken = default);
}
