import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_project_entry.dart';
import '../../services/app/desktop_window_actions.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/notification/notification_bell_button.dart';
import '../../widgets/team_pilot_brand_logo.dart';
import '../../widgets/window_chrome_controls.dart';
import '../../widgets/window_drag_area.dart';
import '../config/config_workspace.dart';

/// Height of the Apifox-style workspace title bar.
const double kHomeTitleBarHeight = 58;

/// Custom window title bar for the new workspace home: brand mark, a "Home"
/// pill, optional open-project tab, decorative action glyphs, and the real
/// minimize/maximize/close controls. Reuses theme tokens only — no hardcoded
/// brand colors.
/// Personal vs team discriminator for title-bar project tabs.
enum HomeWorkspaceTabKind { personal, team }

@visibleForTesting
double homeProjectTabBarAlpha({required bool active, required bool hovered}) {
  if (active) return 1.0;
  if (hovered) return 0.7;
  return 0.4;
}

/// Hue-rotated complement of [base] on the color wheel (反色系).
@visibleForTesting
Color homeProjectTabComplementColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withHue((hsl.hue + 180) % 360).toColor();
}

@visibleForTesting
Color homeProjectTabKindAccentColor({
  required HomeWorkspaceTabKind kind,
  required ColorScheme colorScheme,
}) {
  final personal = colorScheme.primary;
  return kind == HomeWorkspaceTabKind.personal
      ? personal
      : homeProjectTabComplementColor(personal);
}

@visibleForTesting
IconData homeProjectTabKindIcon(HomeWorkspaceTabKind kind) {
  return switch (kind) {
    HomeWorkspaceTabKind.personal => Icons.person_outline_rounded,
    HomeWorkspaceTabKind.team => Icons.groups_2_outlined,
  };
}

@visibleForTesting
Color homeProjectTabBarColor({
  required HomeWorkspaceTabKind kind,
  required ColorScheme colorScheme,
  required bool active,
  required bool hovered,
}) {
  return homeProjectTabKindAccentColor(
    kind: kind,
    colorScheme: colorScheme,
  ).withValues(
    alpha: homeProjectTabBarAlpha(active: active, hovered: hovered),
  );
}

@visibleForTesting
Color homeProjectTabKindIconColor({
  required HomeWorkspaceTabKind kind,
  required ColorScheme colorScheme,
  required bool active,
  required bool hovered,
}) {
  final base = homeProjectTabKindAccentColor(
    kind: kind,
    colorScheme: colorScheme,
  );
  // Keep kind readable on inactive tabs; bar alone was too subtle on warm presets.
  final alpha = active ? 1.0 : (hovered ? 0.9 : 0.8);
  return base.withValues(alpha: alpha);
}

/// An open project tab in the title bar.
class HomeWorkspaceTab {
  const HomeWorkspaceTab({
    required this.id,
    required this.name,
    required this.kind,
    this.tooltip,
    this.closable = true,
  });

  final String id;
  final String name;
  final HomeWorkspaceTabKind kind;

  /// Shown on hover; defaults to [name] when omitted.
  final String? tooltip;

  /// When false (the pinned personal project), no close button is shown.
  final bool closable;
}

class HomeTitleBar extends StatefulWidget {
  const HomeTitleBar({
    this.tabs = const [],
    this.activeProjectId,
    this.pageChrome = WorkspacePageChrome.home,
    this.recentlyClosed = const [],
    this.openProjectIds = const {},
    this.onHomeTap,
    this.onSelectTab,
    this.onCloseTab,
    this.onReopenClosedProject,
    super.key,
  });

  /// Open project tabs, kept until explicitly closed.
  final List<HomeWorkspaceTab> tabs;

  /// The project currently shown, or null when the Home view is shown.
  final String? activeProjectId;

  /// Page backdrop chrome; matches [HomeShell] scaffold fill.
  final WorkspacePageChrome pageChrome;

  /// Recently closed tabs (newest first), excluding currently open ids.
  final List<HomeClosedWorkspaceEntry> recentlyClosed;
  final Set<String> openProjectIds;
  final VoidCallback? onHomeTap;
  final ValueChanged<String>? onSelectTab;
  final ValueChanged<String>? onCloseTab;
  final ValueChanged<String>? onReopenClosedProject;

  @override
  State<HomeTitleBar> createState() => _HomeTitleBarState();
}

class _HomeTitleBarState extends State<HomeTitleBar>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!useCustomDesktopWindowTitleBar) return;
    windowManager.addListener(this);
    _syncExpanded();
  }

  @override
  void dispose() {
    if (useCustomDesktopWindowTitleBar) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncExpanded() async {
    final expanded = await isDesktopWindowExpanded();
    if (!mounted) return;
    setState(() => _isMaximized = expanded);
  }

  @override
  void onWindowMaximize() => unawaited(_syncExpanded());

  @override
  void onWindowUnmaximize() => unawaited(_syncExpanded());

  @override
  void onWindowEnterFullScreen() => unawaited(_syncExpanded());

  @override
  void onWindowLeaveFullScreen() => unawaited(_syncExpanded());

  Future<void> _toggleMaximize({bool optionPressed = false}) async {
    if (Platform.isMacOS) {
      await handleMacGreenButton(optionPressed: optionPressed);
    } else {
      await toggleDesktopWindowExpand();
    }
    await _syncExpanded();
  }

  Widget _buildWindowControls() {
    return WindowChromeControls(
      height: kHomeTitleBarHeight,
      isMaximized: _isMaximized,
      onMinimize: () => windowManagerCall(windowManager.minimize),
      onToggleMaximize: _toggleMaximize,
      onClose: () => windowManagerCall(windowManager.close),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final showWindowControls = useCustomDesktopWindowTitleBar;

    return Material(
      color: cs.workspacePageChrome(widget.pageChrome),
      child: SizedBox(
        height: kHomeTitleBarHeight,
        child: Row(
          children: [
            SizedBox(width: 8),
            if (showWindowControls && useMacWindowChromeStyle)
              _buildWindowControls(),
            SizedBox(width: useMacWindowChromeStyle ? 8 : 20),
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
                                    kind: tab.kind,
                                    active: tab.id == widget.activeProjectId,
                                    closable: tab.closable,
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
            const NotificationBellButton(),
            _ActionGlyph(
              icon: Icons.settings_outlined,
              tooltip: l10n.settings,
              onTap: () => showWorkspaceSettingsDialog(context),
            ),
            const SizedBox(width: 10),
            if (showWindowControls && !useMacWindowChromeStyle)
              _buildWindowControls(),
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
            Icon(Icons.home_filled, size: context.appIconSizes.md, color: fg),
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

class _ProjectTab extends StatefulWidget {
  const _ProjectTab({
    required this.label,
    required this.tooltip,
    required this.kind,
    this.active = false,
    this.closable = true,
    this.onTap,
    this.onClose,
  });

  final String label;
  final String tooltip;
  final HomeWorkspaceTabKind kind;
  final bool active;
  final bool closable;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  State<_ProjectTab> createState() => _ProjectTabState();
}

class _ProjectTabState extends State<_ProjectTab> {
  var _hovered = false;

  /// Touch platforms have no hover; keep tab chrome visible on Android.
  bool get _showChrome => widget.active || _hovered || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final barColor = homeProjectTabBarColor(
      kind: widget.kind,
      colorScheme: cs,
      active: active,
      hovered: _hovered,
    );
    final kindIconColor = homeProjectTabKindIconColor(
      kind: widget.kind,
      colorScheme: cs,
      active: active,
      hovered: _hovered,
    );
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.only(
              left: 10,
              right: 6,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: active
                  ? cs.surfaceContainerHigh
                  : _hovered
                  ? cs.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? cs.outlineVariant.withValues(alpha: 0.7)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Fixed height: CrossAxisAlignment.stretch would expand the row
                // to the ListView viewport height (~full title bar).
                SizedBox(
                  width: 3,
                  height: context.appIconSizes.md,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TabChromeSlot(
                  visible: _showChrome,
                  child: Icon(
                    homeProjectTabKindIcon(widget.kind),
                    size: context.appIconSizes.md,
                    color: kindIconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.bodySmall.copyWith(color: fg),
                  ),
                ),
                if (widget.closable) ...[
                  const SizedBox(width: 8),
                  _TabChromeSlot(
                    visible: _showChrome,
                    child: InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: context.appIconSizes.md,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps tab chrome in the layout while hiding it visually until hover/active.
class _TabChromeSlot extends StatelessWidget {
  const _TabChromeSlot({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// Overflow menu listing recently closed project tabs; opens on hover.
class _RecentlyClosedOverflowButton extends StatefulWidget {
  const _RecentlyClosedOverflowButton({required this.entries, this.onReopen});

  final List<HomeClosedWorkspaceEntry> entries;
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
                            onTap: () => widget.onReopen?.call(entry.projectId),
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
            size: context.appIconSizes.md,
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
