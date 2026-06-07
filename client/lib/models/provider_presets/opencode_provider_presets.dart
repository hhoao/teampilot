import '../app_provider_config.dart';

/// Built-in opencode provider presets.
///
/// The saved provider **id** (slugified from `name`) becomes opencode's
/// provider key — it is what the launch adapter emits as `--model <id>/<model>`
/// and the key written under `provider.<id>.options` in opencode.json. So each
/// preset is named to slugify to a provider id opencode recognises natively
/// (`openai`, `anthropic`, `google`, `openrouter`, `deepseek`, `xai`, `groq`).
///
/// The last preset is a generic OpenAI-compatible template: it carries
/// `config.npm = "@ai-sdk/openai-compatible"` so a custom/proxy endpoint
/// resolves even though its id is not in opencode's catalog. Users fill in the
/// Base URL and API key.
class OpencodeProviderPresets {
  const OpencodeProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: "opencode",
      label: "OpenCode Zen (official)",
      template: AppProviderConfig(
        id: "opencode",
        cli: CliTool.opencode,
        name: "OpenCode",
        websiteUrl: "https://opencode.ai",
        apiKeyUrl: "https://opencode.ai/zen",
        category: AppProviderCategory.official,
        defaultModel: "claude-sonnet-4-5",
        isOfficial: true,
      ),
    ),
    AppProviderPreset(
      id: "openai",
      label: "OpenAI",
      template: AppProviderConfig(
        id: "openai",
        cli: CliTool.opencode,
        name: "OpenAI",
        websiteUrl: "https://openai.com",
        apiKeyUrl: "https://platform.openai.com/api-keys",
        category: AppProviderCategory.official,
        baseUrl: "https://api.openai.com/v1",
        defaultModel: "gpt-4o",
        icon: "openai",
        iconColor: "#00A67E",
        isOfficial: true,
      ),
    ),
    AppProviderPreset(
      id: "anthropic",
      label: "Anthropic (Claude)",
      template: AppProviderConfig(
        id: "anthropic",
        cli: CliTool.opencode,
        name: "Anthropic",
        websiteUrl: "https://www.anthropic.com",
        apiKeyUrl: "https://console.anthropic.com/settings/keys",
        category: AppProviderCategory.official,
        defaultModel: "claude-sonnet-4-5",
        icon: "anthropic",
        iconColor: "#D4915D",
        isOfficial: true,
      ),
    ),
    AppProviderPreset(
      id: "google",
      label: "Google (Gemini)",
      template: AppProviderConfig(
        id: "google",
        cli: CliTool.opencode,
        name: "Google",
        websiteUrl: "https://ai.google.dev",
        apiKeyUrl: "https://aistudio.google.com/apikey",
        category: AppProviderCategory.official,
        defaultModel: "gemini-2.0-flash",
        icon: "gemini",
        isOfficial: true,
      ),
    ),
    AppProviderPreset(
      id: "openrouter",
      label: "OpenRouter",
      template: AppProviderConfig(
        id: "openrouter",
        cli: CliTool.opencode,
        name: "OpenRouter",
        websiteUrl: "https://openrouter.ai",
        apiKeyUrl: "https://openrouter.ai/keys",
        category: AppProviderCategory.aggregator,
        baseUrl: "https://openrouter.ai/api/v1",
        defaultModel: "anthropic/claude-sonnet-4",
        icon: "openrouter",
      ),
    ),
    AppProviderPreset(
      id: "deepseek",
      label: "DeepSeek",
      template: AppProviderConfig(
        id: "deepseek",
        cli: CliTool.opencode,
        name: "DeepSeek",
        websiteUrl: "https://www.deepseek.com",
        apiKeyUrl: "https://platform.deepseek.com/api_keys",
        category: AppProviderCategory.cnOfficial,
        baseUrl: "https://api.deepseek.com",
        defaultModel: "deepseek-chat",
        icon: "deepseek",
      ),
    ),
    AppProviderPreset(
      id: "xai",
      label: "xAI (Grok)",
      template: AppProviderConfig(
        id: "xai",
        cli: CliTool.opencode,
        name: "xAI",
        websiteUrl: "https://x.ai",
        apiKeyUrl: "https://console.x.ai",
        category: AppProviderCategory.official,
        baseUrl: "https://api.x.ai/v1",
        defaultModel: "grok-3",
        isOfficial: true,
      ),
    ),
    AppProviderPreset(
      id: "groq",
      label: "Groq",
      template: AppProviderConfig(
        id: "groq",
        cli: CliTool.opencode,
        name: "Groq",
        websiteUrl: "https://groq.com",
        apiKeyUrl: "https://console.groq.com/keys",
        category: AppProviderCategory.thirdParty,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "llama-3.3-70b-versatile",
      ),
    ),
    AppProviderPreset(
      id: "openai-compatible",
      label: "OpenAI Compatible (custom)",
      template: AppProviderConfig(
        id: "openai-compatible",
        cli: CliTool.opencode,
        name: "OpenAI Compatible",
        category: AppProviderCategory.custom,
        config: {"npm": "@ai-sdk/openai-compatible"},
      ),
    ),
  ];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
