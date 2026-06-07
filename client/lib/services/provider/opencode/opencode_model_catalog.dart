/// Built-in OpenCode model ids for TeamPilot pickers (Zen + common direct APIs).
///
/// Zen ids match https://opencode.ai/docs/zen . A future [ProviderModelCapability]
/// may replace this with a live fetch from `https://opencode.ai/zen/v1/models`.
class OpencodeModelCatalog {
  const OpencodeModelCatalog._();

  static const zen = <String>[
    'big-pickle',
    'claude-sonnet-4-5',
    'claude-sonnet-4-6',
    'claude-sonnet-4',
    'claude-opus-4-8',
    'claude-opus-4-6',
    'claude-opus-4-5',
    'claude-haiku-4-5',
    'gpt-5.5',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.4-nano',
    'gpt-5.2',
    'gpt-5.1',
    'gemini-3-flash',
    'gemini-3.1-pro',
    'gemini-3.5-flash',
    'deepseek-v4-flash',
    'deepseek-v4-flash-free',
    'glm-5.1',
    'glm-5',
    'kimi-k2.5',
    'kimi-k2.6',
    'qwen3.7-max',
    'qwen3.6-plus',
    'qwen3.5-plus',
    'minimax-m2.7',
    'minimax-m2.5',
    'mimo-v2.5-free',
    'nemotron-3-super-free',
    'grok-build-0.1',
  ];

  static const _byProviderId = <String, List<String>>{
    'opencode': zen,
    'openai': [
      'gpt-4o',
      'gpt-4.1',
      'gpt-4.1-mini',
      'o3',
      'o4-mini',
    ],
    'anthropic': [
      'claude-sonnet-4-5',
      'claude-sonnet-4-6',
      'claude-opus-4-6',
      'claude-haiku-4-5',
    ],
    'google': [
      'gemini-2.0-flash',
      'gemini-2.5-pro',
      'gemini-3-flash',
    ],
    'deepseek': [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    'groq': [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
    ],
    'xai': [
      'grok-3',
      'grok-3-mini',
    ],
  };

  static List<String> knownModelsForProvider(String providerId) {
    final id = providerId.trim();
    if (id.isEmpty) return const [];
    return List<String>.unmodifiable(_byProviderId[id] ?? const []);
  }
}
