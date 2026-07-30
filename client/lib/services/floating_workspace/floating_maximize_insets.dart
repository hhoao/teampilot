import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Sidebar-aware maximize safe area relative to [FloatingWorkspaceHost].
///
/// `null` means no workspace layout has published insets yet — the panel
/// maximizes to the full host body (below the title bar).
///
/// When a workspace IDE is active, [WorkspaceIdeShell] publishes
/// `EdgeInsets.only(left: sidebarWidth)` so maximize does not cover the
/// file-tree sidebar.
///
/// Intentionally **not** a [ValueNotifier]/[ChangeNotifier]: those types are
/// rejected by [RepositoryProvider.value] / [Provider.value].
class FloatingMaximizeInsets {
  FloatingMaximizeInsets([EdgeInsets? initial])
    : _notifier = ValueNotifier<EdgeInsets?>(initial);

  final ValueNotifier<EdgeInsets?> _notifier;

  ValueListenable<EdgeInsets?> get listenable => _notifier;

  EdgeInsets? get value => _notifier.value;

  void update(EdgeInsets? next) {
    if (_notifier.value == next) return;
    _notifier.value = next;
  }

  void dispose() => _notifier.dispose();
}
