import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_project_entry.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/team_pilot_brand_logo.dart';
import '../../widgets/window_drag_area.dart';
import '../config/config_workspace.dart';

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
  const HomeProjectTab({
    required this.id,
    required this.name,
    this.tooltip,
  });

  final String id;
  final String name;

  /// Shown on hover; defaults to [name] when omitted.
  final String? tooltip;
}

class HomeWorkspaceTitleBar extends StatefulWidget {
  const HomeWorkspaceTitleBar({
    this.tabs = const [],
    this.activeProjectId,
    this.recentlyClosed = const [],
    this.openProjectIds = const {},
    this.onHomeTap,
    this.onSelectTab,
    this.onCloseTab,
    this.onReopenClosedProject,
    super.key,
  });

  /// Open project tabs, kept until explicitly closed.
  final List<HomeProjectTab> tabs;

  /// The project currently shown, or null when the Home view is shown.
  final String? activeProjectId;

  /// Recently closed tabs (newest first), excluding currently open ids.
  final List<HomeClosedProjectEntry> recentlyClosed;
  final Set<String> openProjectIds;
  final VoidCallback? onHomeTap;
  final ValueChanged<String>? onSelectTab;
  final ValueChanged<String>? onCloseTab;
  final ValueChanged<String>? onReopenClosedProject;

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
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    _RecentlyClosedOverflowButton(
                      entries: widget.recentlyClosed,
                      onReopen: widget.onReopenClosedProject,
                    ),
                    Expanded(
                      child: showWindowControls
                          ? const WindowDragArea(child: SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                  ],
                ),
              )
            else
              // The open project tabs share the remaining width with a single
              // Expanded spacer that doubles as the window-move area, so the
              // action buttons stay flush right with no dead band.
              //
              // The earlier layout paired a Flexible tab strip with a separate
              // Expanded spacer; two flex siblings split the free width 50/50,
              // and the greedy horizontal scroll view filled its half on the
              // left while the right half sat empty. Here the tabs are instead
              // sized to their content (a shrink-wrapping horizontal ListView,
              // capped at the available width so they scroll only when they
              // would overflow), which leaves the spacer as the *sole* flex
              // child: it absorbs all leftover width and remains draggable.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final tab in widget.tabs) ...[
                                const SizedBox(width: 6),
                                // widthFactor keeps the tab at its content
                                // width; the ListView otherwise stretches each
                                // child to the full bar height.
                                Align(
                                  alignment: Alignment.center,
                                  widthFactor: 1,
                                  child: _ProjectTab(
                                    label: tab.name,
                                    tooltip: tab.tooltip ?? tab.name,
                                    active: tab.id == widget.activeProjectId,
                                    onTap: () =>
                                        widget.onSelectTab?.call(tab.id),
                                    onClose: () =>
                                        widget.onCloseTab?.call(tab.id),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Align(
                                alignment: Alignment.center,
                                widthFactor: 1,
                                child: _RecentlyClosedOverflowButton(
                                  entries: widget.recentlyClosed,
                                  onReopen: widget.onReopenClosedProject,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: showWindowControls
                              ? const WindowDragArea(child: SizedBox.expand())
                              : const SizedBox.expand(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(width: 8),
            _ActionGlyph(
              icon: Icons.settings_outlined,
              tooltip: l10n.settings,
              onTap: () => showWorkspaceSettingsDialog(context),
            ),
            const SizedBox(width: 10),
            if (showWindowControls) ...[
              _WinButton(
                tooltip: l10n.windowControlMinimize,
                icon: Icons.remove,
                onPressed: () => _windowManagerCall(windowManager.minimize),
              ),
              _WinButton(
                tooltip: _isMaximized
                    ? l10n.windowControlRestore
                    : l10n.windowControlMaximize,
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
                tooltip: l10n.windowControlClose,
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
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TeamPilotBrandLogo(),
        const SizedBox(width: 8),
        Text(
          l10n.appTitle,
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
    required this.tooltip,
    this.active = false,
    this.onTap,
    this.onClose,
  });

  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.only(
            left: 12,
            right: 6,
            top: 6,
            bottom: 6,
          ),
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
              Icon(
                Icons.description_outlined,
                size: AppIconSizes.md,
                color: fg,
              ),
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
                  child: Icon(
                    Icons.close,
                    size: AppIconSizes.md,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overflow menu listing recently closed project tabs; opens on hover.
class _RecentlyClosedOverflowButton extends StatefulWidget {
  const _RecentlyClosedOverflowButton({
    required this.entries,
    this.onReopen,
  });

  final List<HomeClosedProjectEntry> entries;
  final ValueChanged<String>? onReopen;

  static const _menuMaxHeight = 320.0;
  static const _menuWidth = 280.0;
  static const _closeDelay = Duration(milliseconds: 180);

  @override
  State<_RecentlyClosedOverflowButton> createState() =>
      _RecentlyClosedOverflowButtonState();
}

class _RecentlyClosedOverflowButtonState
    extends State<_RecentlyClosedOverflowButton> {
  final _menuController = MenuController();
  Timer? _closeTimer;
  var _pointerOnAnchor = false;
  var _pointerOnMenu = false;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _cancelCloseTimer() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void _scheduleClose() {
    _cancelCloseTimer();
    _closeTimer = Timer(_RecentlyClosedOverflowButton._closeDelay, () {
      if (!_pointerOnAnchor && !_pointerOnMenu && _menuController.isOpen) {
        _menuController.close();
      }
    });
  }

  void _openMenu() {
    _cancelCloseTimer();
    if (!_menuController.isOpen) {
      _menuController.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final entries = widget.entries;

    return MenuAnchor(
      controller: _menuController,
      style: SidebarActionMenuMetrics.menuAnchorStyle(
        context,
        minWidth: _RecentlyClosedOverflowButton._menuWidth,
      ),
      alignmentOffset: const Offset(0, 4),
      onOpen: _cancelCloseTimer,
      menuChildren: [
        MouseRegion(
          onEnter: (_) {
            _pointerOnMenu = true;
            _cancelCloseTimer();
          },
          onExit: (_) {
            _pointerOnMenu = false;
            _scheduleClose();
          },
          child: SidebarActionMenuPanel(
            minWidth: _RecentlyClosedOverflowButton._menuWidth,
            menuAnchorShell: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Text(
                  l10n.homeWorkspaceRecentlyClosed,
                  style: styles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (entries.isEmpty)
                SidebarActionMenuItem(
                  icon: Icons.inbox_outlined,
                  label: l10n.homeWorkspaceRecentlyClosedEmpty,
                  enabled: false,
                  menuController: _menuController,
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: _RecentlyClosedOverflowButton._menuMaxHeight,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in entries)
                          SidebarActionMenuItem(
                            icon: Icons.description_outlined,
                            label: entry.displayName,
                            subtitle: entry.primaryPath.isEmpty
                                ? null
                                : Text(
                                    entry.primaryPath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: styles.caption.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                            menuController: _menuController,
                            onTap: () =>
                                widget.onReopen?.call(entry.projectId),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        onEnter: (_) {
          _pointerOnAnchor = true;
          _openMenu();
        },
        onExit: (_) {
          _pointerOnAnchor = false;
          _scheduleClose();
        },
        child: _ActionGlyph(
          icon: Icons.more_horiz,
          tooltip: l10n.homeWorkspaceRecentlyClosed,
        ),
      ),
    );
  }
}

class _ActionGlyph extends StatefulWidget {
  const _ActionGlyph({required this.icon, this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<_ActionGlyph> createState() => _ActionGlyphState();
}

class _ActionGlyphState extends State<_ActionGlyph> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget glyph = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
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
          child: Icon(
            widget.icon,
            size: AppIconSizes.md,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) {
      glyph = Tooltip(message: tooltip, child: glyph);
    }
    return glyph;
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
              child: Icon(
                widget.icon,
                size: AppIconSizes.md,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
