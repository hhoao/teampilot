import 'workspace_terminal_registry.dart';

/// IDEA-style tab labels: `Local`, `Local (2)`, `user@host`, …
abstract final class WorkspaceTerminalTitleResolver {
  WorkspaceTerminalTitleResolver._();

  static String tabTitle({
    required WorkspaceTerminalEntry entry,
    required List<WorkspaceTerminalEntry> siblings,
    required String baseLabel,
  }) {
    final sameBase = siblings
        .where((e) => e.titleLabel == baseLabel)
        .toList(growable: false);
    if (sameBase.length <= 1) return baseLabel;
    final index = sameBase.indexWhere((e) => e.id == entry.id) + 1;
    return '$baseLabel ($index)';
  }
}
