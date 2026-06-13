import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/l10n_extensions.dart';
import '../services/app/platform_utils.dart';
import '../theme/app_icon_sizes.dart';

Future<T?> _windowManagerCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MissingPluginException {
    return null;
  }
}

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
    // Resolve the menu anchor synchronously, before any async gap, so the
    // BuildContext is only used while it is guaranteed mounted.
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );

    final maximized =
        await _windowManagerCall(windowManager.isMaximized) ?? false;
    final onTop =
        await _windowManagerCall(windowManager.isAlwaysOnTop) ?? false;
    if (!context.mounted) return;

    final l10n = context.l10n;
    final selected = await showMenu<_WindowMenuAction>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _WindowMenuAction.minimize,
          child: _MenuRow(
            icon: Icons.remove,
            label: l10n.windowControlMinimize,
          ),
        ),
        PopupMenuItem(
          value: maximized
              ? _WindowMenuAction.restore
              : _WindowMenuAction.maximize,
          child: _MenuRow(
            icon: maximized ? Icons.filter_none : Icons.crop_square_outlined,
            label: maximized
                ? l10n.windowControlRestore
                : l10n.windowControlMaximize,
          ),
        ),
        CheckedPopupMenuItem(
          value: _WindowMenuAction.toggleAlwaysOnTop,
          checked: onTop,
          child: Text(l10n.windowControlAlwaysOnTop),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _WindowMenuAction.close,
          child: _MenuRow(icon: Icons.close, label: l10n.windowControlClose),
        ),
      ],
    );

    switch (selected) {
      case _WindowMenuAction.minimize:
        await _windowManagerCall(windowManager.minimize);
      case _WindowMenuAction.maximize:
        await _windowManagerCall(windowManager.maximize);
      case _WindowMenuAction.restore:
        await _windowManagerCall(windowManager.unmaximize);
      case _WindowMenuAction.toggleAlwaysOnTop:
        await _windowManagerCall(() => windowManager.setAlwaysOnTop(!onTop));
      case _WindowMenuAction.close:
        await _windowManagerCall(windowManager.close);
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

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: context.appIconSizes.md),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
