namespace Silen.Common.Options;

/// <summary>Bound from the "OpenRouter" configuration section - the LLM backing the monthly AI analytics feature.</summary>
public sealed class OpenRouterOptions
{
    public const string SectionName = "OpenRouter";

    /// <summary>Bearer token for https://openrouter.ai. Left empty in every committed appsettings file - set via
    /// the OPENROUTER_API_KEY env var (docker-compose) or `dotnet user-secrets` for local `dotnet run`.</summary>
    public string ApiKey { get; set; } = string.Empty;

    /// <summary>Must stay "openai/"-prefixed (or another provider OpenRouter maps to native json_schema support) -
    /// see OpenRouterClient's structured-output request.</summary>
    public string Model { get; set; } = "openai/gpt-4.1";

    public string BaseUrl { get; set; } = "https://openrouter.ai/api/v1/chat/completions";
}
