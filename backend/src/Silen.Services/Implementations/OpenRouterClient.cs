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
    public Task<string> GenerateJsonAsync(
        string systemPrompt, string userPrompt, JsonElement schema, string? model = null,
        CancellationToken cancellationToken = default)
    {
        // The prompt template's own model wins: the deployment-wide OpenRouter:Model
        // override may point at a free/experimental model that doesn't honour
        // json_schema, which would otherwise break every structured response.
        var effectiveModel = string.IsNullOrWhiteSpace(model) ? options.Value.Model : model;

        var body = new
        {
            model = effectiveModel,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = userPrompt }
            },
            response_format = JsonSchemaFormat(schema),
            max_tokens = 4000,
            temperature = 0.05
        };

        return SendAsync(body, cancellationToken);
    }

    public Task<string> GenerateJsonFromImageAsync(
        string systemPrompt, string userPrompt, byte[] image, string imageMediaType, JsonElement schema,
        string model, string reasoningEffort, int maxTokens, CancellationToken cancellationToken = default)
    {
        var dataUrl = $"data:{imageMediaType};base64,{Convert.ToBase64String(image)}";

        // No temperature: vision-capable flagship models are reasoning models, which
        // reject it; "reasoning.effort" is the knob that trades cost for accuracy.
        var body = new
        {
            model,
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new { type = "text", text = userPrompt },
                        new { type = "image_url", image_url = new { url = dataUrl, detail = "high" } }
                    }
                }
            },
            response_format = JsonSchemaFormat(schema),
            reasoning = new { effort = reasoningEffort, exclude = true },
            max_tokens = maxTokens
        };

        return SendAsync(body, cancellationToken);
    }

    private static object JsonSchemaFormat(JsonElement schema) => new
    {
        type = "json_schema",
        json_schema = new
        {
            name = "response",
            strict = true,
            schema
        }
    };

    private async Task<string> SendAsync(object body, CancellationToken cancellationToken)
    {
        var settings = options.Value;
        if (string.IsNullOrWhiteSpace(settings.ApiKey))
        {
            throw new ConflictException("OpenRouter API key is not configured.", "AI insights are temporarily unavailable.");
        }

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
