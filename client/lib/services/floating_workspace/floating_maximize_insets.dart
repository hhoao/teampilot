import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/workspace_surface_layers.dart';
import '../../widgets/workspace_status_bar/workspace_status_bar.dart';

/// Maximize safe area relative to [FloatingWorkspaceHost].
///
/// When unset (`null`), the panel falls back to [cardSafeArea] (home / before
/// a workspace IDE has published). A workspace IDE publishes a tighter rect
/// that also excludes a docked right-tools pane.
///
/// Intentionally **not** a [ValueNotifier]/[ChangeNotifier]: those types are
/// rejected by [RepositoryProvider.value] / [Provider.value].
class FloatingMaximizeInsets {
  FloatingMaximizeInsets([EdgeInsets? initial])
    : _notifier = ValueNotifier<EdgeInsets?>(initial);

  final ValueNotifier<EdgeInsets?> _notifier;

  ValueListenable<EdgeInsets?> get listenable => _notifier;

  EdgeInsets? get value => _notifier.value;

  /// Card padding + status bar — home maximize / fallback when no IDE insets.
  ///
  /// Matches [WorkspacePageCardShell] with `omitBottomPadding: true`.
  static EdgeInsets cardSafeArea({double extraRight = 0}) {
    final card = WorkspacePageCardShell.padding;
    return EdgeInsets.fromLTRB(
      card.left,
      card.top,
      card.right + extraRight,
      WorkspaceStatusBar.totalHeight,
    );
  }

  void update(EdgeInsets? next) {
    if (_notifier.value == next) return;
    _notifier.value = next;
  }

  void dispose() => _notifier.dispose();
}
