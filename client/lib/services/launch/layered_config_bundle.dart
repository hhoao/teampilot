import '../../models/config_bundle.dart';

abstract final class LayeredConfigBundle {
  LayeredConfigBundle._();

  /// Union with precedence: [team] > [expert] > [workspace].
  static ConfigBundle merge({
    ConfigBundle? team,
    ConfigBundle? expert,
    required ConfigBundle workspace,
  }) {
    return ConfigBundle(
      skillIds: _mergeIds(workspace.skillIds, expert?.skillIds, team?.skillIds),
      pluginIds: _mergeIds(
        workspace.pluginIds,
        expert?.pluginIds,
        team?.pluginIds,
      ),
      mcpServerIds: _mergeIds(
        workspace.mcpServerIds,
        expert?.mcpServerIds,
        team?.mcpServerIds,
      ),
    );
  }

  static List<String> _mergeIds(
    List<String> workspace,
    List<String>? expert,
    List<String>? team,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void addAll(Iterable<String>? ids) {
      if (ids == null) return;
      for (final raw in ids) {
        final id = raw.trim();
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        out.add(id);
      }
    }

    // Higher layers first so first-seen wins = precedence.
    addAll(team);
    addAll(expert);
    addAll(workspace);
    return List.unmodifiable(out);
  }
}
