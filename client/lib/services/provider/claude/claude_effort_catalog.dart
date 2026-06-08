/// Claude Code `effortLevel` values and model applicability heuristics.
///
/// Mirrors Claude Code `EFFORT_LEVELS` / `modelSupportsEffort` (simplified).
abstract final class ClaudeEffortCatalog {
  ClaudeEffortCatalog._();

  static const levels = <String>[
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

  static const defaultLevel = 'high';

  static bool modelSupportsEffort(String model) {
    final m = model.trim().toLowerCase();
    if (m.isEmpty) return true;
    if (m == 'sonnet' || m == 'opus' || m == 'haiku' || m == 'best') {
      return true;
    }
    if (m.contains('opus-4-7') ||
        m.contains('opus-4-6') ||
        m.contains('sonnet-4-6')) {
      return true;
    }
    if (m.contains('haiku')) return false;
    if (m.contains('sonnet') || m.contains('opus')) {
      return m.contains('-4');
    }
    return true;
  }

  static List<String> levelsForModel(String model) {
    if (!modelSupportsEffort(model)) return const [];
    return List<String>.from(levels);
  }
}
