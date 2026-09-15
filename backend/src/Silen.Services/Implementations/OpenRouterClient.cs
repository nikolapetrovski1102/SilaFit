using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Silen.Common.Exceptions;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IOpenRouterClient"/>
/// <remarks>Ported (simplified to a single JSON-schema-capable model) from the WayR project's
/// AIProvider.GenerateOpenRouterAsync - Silen only ever targets one "openai/"-prefixed model, so the
/// multi-provider/multi-model branching that project needed isn't required here.</remarks>
public sealed class OpenRouterClient(HttpClient httpClient, IOptions<OpenRouterOptions> options) : IOpenRouterClient
{
    public async Task<string> GenerateJsonAsync(
        string systemPrompt, string userPrompt, JsonElement schema, CancellationToken cancellationToken = default)
    {
        var settings = options.Value;
        if (string.IsNullOrWhiteSpace(settings.ApiKey))
        {
            throw new ConflictException("OpenRouter API key is not configured.", "AI insights are temporarily unavailable.");
        }

        var body = new
        {
            model = settings.Model,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = userPrompt }
            },
            response_format = new
            {
                type = "json_schema",
                json_schema = new
                {
                    name = "response",
                    strict = true,
                    schema
                }
            },
            max_tokens = 4000,
            temperature = 0.05
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, settings.BaseUrl);
        request.Headers.Authorization = new("Bearer", settings.ApiKey);
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            // Never log the upstream body: it can echo prompt content. The status
            // code is enough to tell an outage from a rejected request.
            throw new ConflictException(
                $"OpenRouter API returned status {(int)response.StatusCode}.",
                "AI insights are temporarily unavailable. Please try again shortly.");
        }

        var result = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: cancellationToken).ConfigureAwait(false);
        var content = result.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString();
        if (string.IsNullOrWhiteSpace(content))
        {
            throw new ConflictException("OpenRouter returned an empty response.", "AI insights are temporarily unavailable.");
        }

        return content;
    }
}
