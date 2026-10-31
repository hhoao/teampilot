/// Built-in OpenCode model ids for TeamPilot pickers (Zen + common direct APIs).
///
/// The Zen / OpenCode Go columns are the **served** ids from the providers'
/// own endpoints (`https://opencode.ai/zen/v1/models` and
/// `.../zen/go/v1/models`), refreshed 2026-10-31. They are deliberately not
/// taken from `models.dev`: that catalog keeps retired ids (e.g.
/// `deepseek-v4-flash-free`) long after the endpoint stops serving them, and a
/// picker that offers one produces `Model is unavailable` at launch.
/// [OpencodeModelsService] re-reads the endpoints at runtime; this table is
/// only the offline / cold-start fallback.
///
/// Launch-time model validation treats "not in this table" as "custom model
/// id" and lets it through — a stale table degrades the check instead of
/// failing loudly, which is why the table must track the endpoints.
class OpencodeModelCatalog {
  const OpencodeModelCatalog._();

  static const zen = <String>[
    'beam-free',
    'big-pickle',
    'claude-fable-5',
    'claude-fable-5-1',
    'claude-haiku-4-5',
    'claude-haiku-5-5',
    'claude-opus-4-5',
    'claude-opus-4-6',
    'claude-opus-4-7',
    'claude-opus-4-8',
    'claude-opus-5',
    'claude-opus-5-5',
    'claude-sonnet-4-5',
    'claude-sonnet-4-6',
    'claude-sonnet-5',
    'claude-sonnet-5-5',
    'deepseek-v4-pro',
    'deepseek-v4.1-flash',
    'deepseek-v4.1-flash-free',
    'flint-40b-free',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-3.7-flash',
    'gemini-3.8-flash',
    'gemini-4-argon',
    'glm-5',
    'glm-5.1',
    'glm-5.2',
    'glm-5.3',
    'glm-5.3-flash',
    'glm-5.3-flash-free',
    'gpt-5',
    'gpt-5-codex',
    'gpt-5-nano',
    'gpt-5.1',
    'gpt-5.1-codex',
    'gpt-5.1-codex-max',
    'gpt-5.1-codex-mini',
    'gpt-5.2',
    'gpt-5.2-codex',
    'gpt-5.3-codex',
    'gpt-5.3-codex-spark',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.4-nano',
    'gpt-5.4-pro',
    'gpt-5.5',
    'gpt-5.5-pro',
    'gpt-5.6-luna',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'gpt-6-astra',
    'gpt-6-luna',
    'gpt-6-sol',
    'gpt-6.1-sol',
    'grok-4.5',
    'grok-4.6',
    'grok-4.7',
    'grok-build-0.1',
    'kimi-k2.5',
    'kimi-k2.6',
    'kimi-k2.7-code',
    'kimi-k3',
    'mimo-v2.6-flash-free',
    'minimax-m2.5',
    'minimax-m2.7',
    'minimax-m3',
    'mistral-large-4',
    'muse-spark-1.2',
    'muse-spark-1.3',
    'muse-wonder-1.0',
    'nemotron-3.5-lightning-free',
    'nemotron-3.5-super-vl-free',
    'qwen3.5-plus',
    'qwen3.6-plus',
    'qwen3.8-flash',
    'qwen3.8-max',
  ];

  static const _byProviderId = <String, List<String>>{
    'opencode': zen,
    'opencode-go': [
      'beam-free',
      'claude-haiku-5-5',
      'deepseek-v4-pro',
      'deepseek-v4.1-flash',
      'gemini-4-argon',
      'glm-5.2',
      'glm-5.3',
      'glm-5.3-flash',
      'gpt-5.6-luna',
      'gpt-6-luna',
      'grok-4.7',
      'hy3',
      'hy4-preview',
      'iceman-contributor-free',
      'kimi-k2.7-code',
      'kimi-k3',
      'kimi-k3.1-pro',
      'longcat-2.0',
      'mimo-v2.6-flash',
      'mimo-v2.6-pro',
      'minimax-m3',
      'minimax-m3.1-flash',
      'muse-spark-1.2-contributor',
      'muse-spark-1.3-contributor',
      'qwen3.7-plus',
      'qwen3.8-flash',
      'qwen3.8-max',
      'step-5-preview',
    ],
    'openai': ['gpt-4o', 'gpt-4.1', 'gpt-4.1-mini', 'o3', 'o4-mini'],
    'anthropic': [
      'claude-sonnet-4-5',
      'claude-sonnet-4-6',
      'claude-opus-4-6',
      'claude-haiku-4-5',
    ],
    'google': ['gemini-2.0-flash', 'gemini-2.5-pro', 'gemini-3-flash'],
    'deepseek': ['deepseek-chat', 'deepseek-reasoner'],
    'groq': [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
    ],
    'xai': ['grok-3', 'grok-3-mini'],
  };

  static List<String> knownModelsForProvider(String providerId) {
    final id = providerId.trim();
    if (id.isEmpty) return const [];
    return List<String>.unmodifiable(_byProviderId[id] ?? const []);
  }
}
