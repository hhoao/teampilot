import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/l10n_extensions.dart';
import '../services/app/desktop_window_actions.dart';
import '../services/app/platform_utils.dart';
import 'package:shared_ui/shared_ui.dart';

/// Wraps [child] in the window-move area and restores the interactions a native
/// title bar would provide on a frameless window:
///
/// * drag to move and double-click to maximize/restore — already provided by
///   [DragToMoveArea];
/// * a right-click window menu (minimize / maximize / restore / always-on-top /
///   close) — added here, since a frameless GTK window has no native one.
///
/// The window operations themselves are delegated to window_manager; this
/// widget only supplies the menu UI and the secondary-tap gesture. On Android
/// (no custom title bar) it returns [child] unchanged.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({required this.child, super.key});

  final Widget child;

  Future<void> _showWindowMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final expanded = await isDesktopWindowExpanded();
    final onTop = await windowManagerCall(windowManager.isAlwaysOnTop) ?? false;
    if (!context.mounted) return;

    final l10n = context.l10n;
    final selected = await showTpActionMenuFromSpecs<_WindowMenuAction>(
      context: context,
      globalPosition: globalPosition,
      specs: [
        TpActionMenuSpec.item(
          value: _WindowMenuAction.minimize,
          icon: Icons.remove,
          label: l10n.windowControlMinimize,
        ),
        TpActionMenuSpec.item(
          value: expanded
              ? _WindowMenuAction.restore
              : _WindowMenuAction.maximize,
          icon: expanded ? Icons.filter_none : Icons.crop_square_outlined,
          label: expanded
              ? l10n.windowControlRestore
              : l10n.windowControlMaximize,
        ),
        TpActionMenuSpec.item(
          value: _WindowMenuAction.toggleAlwaysOnTop,
          icon: Icons.push_pin_outlined,
          label: l10n.windowControlAlwaysOnTop,
          selected: onTop,
        ),
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: _WindowMenuAction.close,
          icon: Icons.close,
          label: l10n.windowControlClose,
          destructive: true,
        ),
      ],
    );

    switch (selected) {
      case _WindowMenuAction.minimize:
        await windowManagerCall(windowManager.minimize);
      case _WindowMenuAction.maximize:
      case _WindowMenuAction.restore:
        await toggleDesktopWindowExpand();
      case _WindowMenuAction.toggleAlwaysOnTop:
        await windowManagerCall(() => windowManager.setAlwaysOnTop(!onTop));
      case _WindowMenuAction.close:
        await windowManagerCall(windowManager.close);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!useCustomDesktopWindowTitleBar) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          _showWindowMenu(context, details.globalPosition),
      child: DragToMoveArea(child: child),
    );
  }
}

enum _WindowMenuAction { minimize, maximize, restore, toggleAlwaysOnTop, close }
