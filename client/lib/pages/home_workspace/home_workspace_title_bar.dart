import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// Height of the Apifox-style workspace title bar.
const double kHomeWorkspaceTitleBarHeight = 58;

Future<T?> _windowManagerCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MissingPluginException {
    return null;
  }
}

/// Custom window title bar for the new workspace home: brand mark, a "Home"
/// pill, optional open-project tab, decorative action glyphs, and the real
/// minimize/maximize/close controls. Reuses theme tokens only — no hardcoded
/// brand colors.
/// An open project tab in the title bar.
class HomeProjectTab {
  const HomeProjectTab({required this.id, required this.name});

  final String id;
  final String name;
}

class HomeWorkspaceTitleBar extends StatefulWidget {
  const HomeWorkspaceTitleBar({
    this.tabs = const [],
    this.activeProjectId,
    this.onHomeTap,
    this.onSelectTab,
    this.onCloseTab,
    super.key,
  });

  /// Open project tabs, kept until explicitly closed.
  final List<HomeProjectTab> tabs;

  /// The project currently shown, or null when the Home view is shown.
  final String? activeProjectId;
  final VoidCallback? onHomeTap;
  final ValueChanged<String>? onSelectTab;
  final ValueChanged<String>? onCloseTab;

  @override
  State<HomeWorkspaceTitleBar> createState() => _HomeWorkspaceTitleBarState();
}

class _HomeWorkspaceTitleBarState extends State<HomeWorkspaceTitleBar>
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
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final showWindowControls = useCustomDesktopWindowTitleBar;

    return Material(
      color: cs.workspacePage,
      child: SizedBox(
        height: kHomeWorkspaceTitleBarHeight,
        child: Row(
          children: [
            const SizedBox(width: 20),
            const _BrandMark(),
            const SizedBox(width: 24),
            _HomePill(
              label: l10n.homeWorkspaceMainWindow,
              active: widget.activeProjectId == null,
              onTap: widget.onHomeTap,
            ),
            if (widget.tabs.isEmpty)
              Expanded(
                child: showWindowControls
                    ? const DragToMoveArea(child: SizedBox.expand())
                    : const SizedBox.expand(),
              )
            else
              // Tabs take all remaining space as the sole flex child. Previously
              // a Flexible tab strip and a separate Expanded spacer both carried
              // flex, so the free width was split 50/50: the greedy horizontal
              // scroll view filled its half on the left while the spacer left a
              // dead band on the right. Filling the whole gap keeps the tabs
              // left-aligned, the action buttons flush right, and removes the
              // wasted space.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in widget.tabs) ...[
                        const SizedBox(width: 6),
                        _ProjectTab(
                          label: tab.name,
                          active: tab.id == widget.activeProjectId,
                          onTap: () => widget.onSelectTab?.call(tab.id),
                          onClose: () => widget.onCloseTab?.call(tab.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const _ActionGlyph(icon: Icons.settings_outlined),
            const _ActionGlyph(icon: Icons.notifications_none_rounded),
            const SizedBox(width: 6),
            const _Avatar(),
            const SizedBox(width: 10),
            if (showWindowControls) ...[
              _WinButton(
                tooltip: 'Minimize',
                icon: Icons.remove,
                onPressed: () => _windowManagerCall(windowManager.minimize),
              ),
              _WinButton(
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
              _WinButton(
                tooltip: 'Close',
                icon: Icons.close,
                isClose: true,
                onPressed: () => _windowManagerCall(windowManager.close),
              ),
            ],
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.tertiary],
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            Icons.flight_takeoff_rounded,
            size: AppIconSizes.md,
            color: cs.onPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'TeamPilot',
          style: styles.bodyStrong.copyWith(color: cs.onSurface),
        ),
      ],
    );
  }
}

class _HomePill extends StatelessWidget {
  const _HomePill({required this.label, this.active = true, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_filled, size: AppIconSizes.md, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: styles.bodySmall.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTab extends StatelessWidget {
  const _ProjectTab({
    required this.label,
    this.active = false,
    this.onTap,
    this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: active ? cs.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? cs.outlineVariant.withValues(alpha: 0.7)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: AppIconSizes.md, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.bodySmall.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: AppIconSizes.md, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGlyph extends StatefulWidget {
  const _ActionGlyph({required this.icon});

  final IconData icon;

  @override
  State<_ActionGlyph> createState() => _ActionGlyphState();
}

class _ActionGlyphState extends State<_ActionGlyph> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _hovered
              ? cs.onSurface.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(widget.icon, size: AppIconSizes.md, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.tertiary, cs.primary],
        ),
      ),
      child: Icon(Icons.person, size: AppIconSizes.md, color: cs.onPrimary),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
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
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
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
          height: kHomeWorkspaceTitleBarHeight,
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
