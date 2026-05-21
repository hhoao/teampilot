import '../app_provider_config.dart';

/// Built-in FlashskyAI [llm_config.json] provider templates.
///
/// Shapes match a typical FlashskyAI install (API + account providers, Anthropic
/// and OpenAI-compatible endpoints). Presets never ship real API keys.
class FlashskyaiProviderPresets {
  const FlashskyaiProviderPresets._();

  static const all = <AppProviderPreset>[
    AppProviderPreset(
      id: 'DeepSeek',
      label: 'DeepSeek',
      template: AppProviderConfig(
        id: 'DeepSeek',
        cli: AppProviderCli.flashskyai,
        name: 'DeepSeek',
        websiteUrl: 'https://platform.deepseek.com',
        category: AppProviderCategory.cnOfficial,
        apiKeyField: 'api_key',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
        icon: 'deepseek',
        config: {
          'type': 'api',
          'proxy': false,
          'provider_type': 'openai',
          'models': {
            'deepseek-chat': {
              'name': 'deepseek-chat',
              'provider': 'DeepSeek',
              'model': 'deepseek-chat',
              'enabled': true,
            },
            'deepseek-v4-pro[1m]': {
              'name': 'deepseek-v4-pro[1m]',
              'provider': 'DeepSeek',
              'model': 'deepseek-v4-pro[1m]',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'Local-Ollama',
      label: 'Local Ollama',
      template: AppProviderConfig(
        id: 'Local-Ollama',
        cli: AppProviderCli.flashskyai,
        name: 'Local-Ollama',
        category: AppProviderCategory.custom,
        apiKeyField: 'api_key',
        baseUrl: 'https://127.0.0.1:11434/',
        defaultModel: 'qwen3-next-80b-a3b-nothink-q4:latest',
        config: {
          'type': 'api',
          'proxy': false,
          'provider_type': 'openai',
          'models': {
            'local-qwen-next-80b': {
              'name': 'qwen3-next-80b-a3b-nothink-q4:latest',
              'provider': 'Local-Ollama',
              'model': 'qwen3-next-80b-a3b-nothink-q4:latest',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'Minimaxi',
      label: 'MiniMax',
      template: AppProviderConfig(
        id: 'Minimaxi',
        cli: AppProviderCli.flashskyai,
        name: 'Minimaxi',
        websiteUrl: 'https://platform.minimaxi.com',
        category: AppProviderCategory.cnOfficial,
        apiKeyField: 'api_key',
        baseUrl: 'https://api.minimaxi.com/anthropic',
        defaultModel: 'MiniMax-M2.7',
        icon: 'minimax',
        config: {
          'type': 'api',
          'proxy': false,
          'provider_type': 'minimaxi',
          'models': {
            'MiniMax-M2.7': {
              'name': 'MiniMax-M2.7',
              'provider': 'Minimaxi',
              'model': 'MiniMax-M2.7',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'aliyun',
      label: 'Aliyun DashScope',
      template: AppProviderConfig(
        id: 'aliyun',
        cli: AppProviderCli.flashskyai,
        name: 'aliyun',
        websiteUrl: 'https://dashscope.aliyun.com',
        category: AppProviderCategory.cloudProvider,
        apiKeyField: 'api_key',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/',
        defaultModel: 'qwen-plus',
        icon: 'alibaba',
        config: {
          'type': 'api',
          'proxy': false,
          'provider_type': 'openai',
          'models': {
            'qwen-plus': {
              'name': 'qwen-plus',
              'provider': 'aliyun',
              'model': 'qwen-plus',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'nvidia',
      label: 'NVIDIA Integrate API',
      template: AppProviderConfig(
        id: 'nvidia',
        cli: AppProviderCli.flashskyai,
        name: 'nvidia',
        websiteUrl: 'https://build.nvidia.com',
        category: AppProviderCategory.cloudProvider,
        apiKeyField: 'api_key',
        baseUrl: 'https://integrate.api.nvidia.com/v1/',
        defaultModel: 'z-ai/glm5',
        icon: 'nvidia',
        config: {
          'type': 'api',
          'proxy': true,
          'proxy_url': 'http://127.0.0.1:8118',
          'provider_type': 'openai',
          'models': {
            'z-ai/glm5': {
              'name': 'z-ai/glm5',
              'provider': 'nvidia',
              'model': 'z-ai/glm5',
              'enabled': true,
            },
            'minimaxai/minimax-m2.1': {
              'name': 'minimaxai/minimax-m2.1',
              'provider': 'nvidia',
              'model': 'minimaxai/minimax-m2.1',
              'enabled': true,
            },
            'moonshotai/kimi-k2.5': {
              'name': 'moonshotai/kimi-k2.5',
              'provider': 'nvidia',
              'model': 'moonshotai/kimi-k2.5',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'Siliconflow',
      label: 'SiliconFlow',
      template: AppProviderConfig(
        id: 'Siliconflow',
        cli: AppProviderCli.flashskyai,
        name: 'Siliconflow',
        websiteUrl: 'https://siliconflow.cn',
        apiKeyUrl: 'https://cloud.siliconflow.cn',
        category: AppProviderCategory.cnOfficial,
        apiKeyField: 'api_key',
        baseUrl: 'https://api.siliconflow.cn/v1',
        defaultModel: '',
        icon: 'siliconflow',
        config: {'type': 'api', 'proxy': false, 'provider_type': 'siliconflow'},
      ),
    ),
    AppProviderPreset(
      id: 'Codex',
      label: 'Codex (account)',
      template: AppProviderConfig(
        id: 'Codex',
        cli: AppProviderCli.flashskyai,
        name: 'Codex',
        websiteUrl: 'https://chatgpt.com/codex',
        category: AppProviderCategory.official,
        apiKeyField: 'api_key',
        defaultModel: 'gpt-5.5',
        icon: 'openai',
        iconColor: '#00A67E',
        isOfficial: true,
        config: {
          'type': 'account',
          'proxy': false,
          'account': ['~/.codex/auth.json'],
          'models': {
            'gpt-5.5': {
              'name': 'gpt-5.5',
              'provider': 'Codex',
              'model': 'gpt-5.5',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'Claude',
      label: 'Claude (account)',
      template: AppProviderConfig(
        id: 'Claude',
        cli: AppProviderCli.flashskyai,
        name: 'Claude',
        websiteUrl: 'https://www.anthropic.com/claude-code',
        category: AppProviderCategory.official,
        apiKeyField: 'api_key',
        defaultModel: 'Sonnet',
        icon: 'anthropic',
        iconColor: '#D4915D',
        isOfficial: true,
        config: {
          'type': 'account',
          'proxy': false,
          'account': ['~/.claude/.credentials.json'],
          'models': {
            'Pro/moonshotai/Kimi-K2.5': {
              'name': 'Pro/moonshotai/Kimi-K2.5',
              'provider': 'Claude',
              'model': 'Pro/moonshotai/Kimi-K2.5',
              'enabled': true,
            },
            'Sonnet': {
              'name': 'Sonnet',
              'provider': 'Claude',
              'model': 'Sonnet',
              'enabled': true,
            },
            'opus': {
              'name': 'opus',
              'provider': 'Claude',
              'model': 'opus',
              'enabled': true,
            },
          },
        },
      ),
    ),
    AppProviderPreset(
      id: 'GeminiAccount',
      label: 'Gemini (account)',
      template: AppProviderConfig(
        id: 'GeminiAccount',
        cli: AppProviderCli.flashskyai,
        name: 'GeminiAccount',
        websiteUrl: 'https://ai.google.dev',
        category: AppProviderCategory.official,
        apiKeyField: 'api_key',
        defaultModel: 'gemini-3.1-pro-preview',
        icon: 'gemini',
        config: {
          'type': 'account',
          'proxy': true,
          'proxy_url': 'http://127.0.0.1:8118',
          'account': ['~/.gemini/oauth_creds.json'],
          'models': {
            'gemini-3.1-pro-preview': {
              'name': 'gemini-3.1-pro-preview',
              'provider': 'GeminiAccount',
              'model': 'gemini-3.1-pro-preview',
              'enabled': true,
            },
            'gemini-2.5-flash': {
              'name': 'gemini-2.5-flash',
              'provider': 'GeminiAccount',
              'model': 'gemini-2.5-flash',
              'enabled': true,
            },
          },
        },
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
