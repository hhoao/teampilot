import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/workspace_surface_layers.dart';
import '../../widgets/workspace_status_bar/workspace_status_bar.dart';

/// Maximize safe area relative to [FloatingWorkspaceHost].
///
/// When unset (`null`), the panel falls back to [cardSafeArea] (home / before
/// a workspace IDE has published). Workspace IDE republishes the same card
/// safe area (maximized panel covers docked right-tools as well).
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
  /// On [isMobile], horizontal card insets and the status-bar height are
  /// omitted (mobile hides the bar and uses a full-bleed card).
  static EdgeInsets cardSafeArea({
    double extraRight = 0,
    bool isMobile = false,
  }) {
    final card = WorkspacePageCardShell.padding;
    return EdgeInsets.fromLTRB(
      isMobile ? 0 : card.left,
      card.top,
      (isMobile ? 0 : card.right) + extraRight,
      isMobile ? 0 : WorkspaceStatusBar.totalHeight,
    );
  }

  void update(EdgeInsets? next) {
    if (_notifier.value == next) return;
    _notifier.value = next;
  }

  void dispose() => _notifier.dispose();
}
