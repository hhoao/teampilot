import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app/platform_utils.dart';
import '../theme/app_text_styles.dart';

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
/// — see [main.dart].
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

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
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
              Expanded(
                child: DragToMoveArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.of(context).bodyStrong.copyWith(
                          color: titleColor.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _WindowChromeButton(
                tooltip: 'Minimize',
                icon: Icons.remove,
                onPressed: () => _windowManagerCall(windowManager.minimize),
              ),
              _WindowChromeButton(
                tooltip: _isMaximized ? 'Restore' : 'Maximize',
                icon: _isMaximized
                    ? Icons.filter_none
                    : Icons.crop_square_outlined,
                onPressed: () async {
                  if (_isMaximized) {
                    await _windowManagerCall(windowManager.unmaximize);
                  } else {
                    await _windowManagerCall(windowManager.maximize);
                  }
                  await _syncMaximized();
                },
              ),
              _WindowChromeButton(
                tooltip: 'Close',
                icon: Icons.close,
                isClose: true,
                onPressed: () => _windowManagerCall(windowManager.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowChromeButton extends StatefulWidget {
  const _WindowChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  State<_WindowChromeButton> createState() => _WindowChromeButtonState();
}

class _WindowChromeButtonState extends State<_WindowChromeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color background = Colors.transparent;
    Color foreground = isDark
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFF374151);

    if (_hovered) {
      if (widget.isClose) {
        background = const Color(0xFFE81123);
        foreground = Colors.white;
      } else {
        background = isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06);
      }
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: 46,
          height: kDesktopWindowTitleBarHeight,
          child: Material(
            color: background,
            child: InkWell(
              onTap: () => widget.onPressed(),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Icon(widget.icon, size: AppIconSizes.md, color: foreground),
            ),
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
