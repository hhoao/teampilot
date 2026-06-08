/// Codex `config.toml` `model_reasoning_effort` values.
abstract final class CodexEffortCatalog {
  CodexEffortCatalog._();

  static const levels = <String>[
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
  ];

  static const defaultLevel = 'high';

  static bool modelSupportsEffort(String model) {
    final m = model.trim().toLowerCase();
    if (m.isEmpty) return true;
    return m.contains('gpt') ||
        m.contains('codex') ||
        m.contains('o3') ||
        m.contains('o4');
  }

  static List<String> levelsForModel(String model) {
    if (!modelSupportsEffort(model)) return const [];
    return List<String>.from(levels);
  }
}
