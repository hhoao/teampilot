import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app/platform_utils.dart';
import '../theme/app_text_styles.dart';
import 'window_chrome_controls.dart';
import 'window_drag_area.dart';

/// Height of the in-app replacement for the native window title bar.
const double kDesktopWindowTitleBarHeight = 40;

Future<T?> _windowManagerCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MissingPluginException {
    return null;
  }
}

/// Desktop-only custom title bar (minimize / maximize / close).
///
/// Requires [TitleBarStyle.hidden] and [windowButtonVisibility] false at startup
/// — see [main.dart]. On macOS the controls are left-aligned traffic lights;
/// on Linux and Windows they stay on the right in Windows style.
class DesktopWindowTitleBar extends StatefulWidget {
  const DesktopWindowTitleBar({
    this.title = 'TeamPilot',
    super.key,
  });

  final String title;

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!useCustomDesktopWindowTitleBar) return;
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    if (useCustomDesktopWindowTitleBar) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await _windowManagerCall(windowManager.isMaximized);
    if (!mounted || maximized == null) return;
    setState(() => _isMaximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await _windowManagerCall(windowManager.unmaximize);
    } else {
      await _windowManagerCall(windowManager.maximize);
    }
    await _syncMaximized();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  Widget _buildWindowControls() {
    return WindowChromeControls(
      height: kDesktopWindowTitleBarHeight,
      isMaximized: _isMaximized,
      onMinimize: () => _windowManagerCall(windowManager.minimize),
      onToggleMaximize: _toggleMaximize,
      onClose: () => _windowManagerCall(windowManager.close),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!useCustomDesktopWindowTitleBar) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);

    final title = Padding(
      padding: EdgeInsets.only(left: useMacWindowChromeStyle ? 8 : 16),
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.of(context).bodyStrong.copyWith(
          color: titleColor.withValues(alpha: 0.9),
        ),
      ),
    );

    return Material(
      color: cs.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: SizedBox(
          height: kDesktopWindowTitleBarHeight,
          child: Row(
            children: [
              if (useMacWindowChromeStyle) _buildWindowControls(),
              Expanded(
                child: WindowDragArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: title,
                  ),
                ),
              ),
              if (!useMacWindowChromeStyle) _buildWindowControls(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] with [DesktopWindowTitleBar] on desktop targets.
class DesktopWindowChrome extends StatelessWidget {
  const DesktopWindowChrome({
    required this.child,
    this.title = 'TeamPilot',
    super.key,
  });

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (!useCustomDesktopWindowTitleBar) {
      return child;
    }

    return Column(
      children: [
        DesktopWindowTitleBar(title: title),
        Expanded(child: child),
      ],
    );
  }
}
