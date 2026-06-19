/// Cursor `--reasoning-effort` values and model applicability heuristics.
abstract final class CursorEffortCatalog {
  CursorEffortCatalog._();

  static const levels = <String>['low', 'medium', 'high'];

  static const defaultLevel = 'medium';

  static bool modelSupportsEffort(String model) {
    final m = model.trim().toLowerCase();
    if (m.isEmpty) return false;
    if (m.contains('thinking')) return true;
    if (m.startsWith('o1') || m.startsWith('o3')) return true;
    if (m.contains('gpt-5')) return true;
    if (m.contains('grok')) return true;
    if (m.contains('opus') || m.contains('sonnet-4')) return true;
    return false;
  }

  static List<String> levelsForModel(String model) {
    if (!modelSupportsEffort(model)) return const [];
    return List<String>.from(levels);
  }
}
