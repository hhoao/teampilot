import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/mobile_workspace_drawer.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../services/app/desktop_window_actions.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../theme/workspace_topology_colors.dart';
import '../../widgets/tab_close_button.dart';
import '../../widgets/notification/notification_bell_button.dart';
import '../../widgets/android_work_environment_selector.dart';
import '../../widgets/team_pilot_brand_logo.dart';
import '../../widgets/window_chrome_controls.dart';
import '../../widgets/window_drag_area.dart';
import '../config/config_workspace.dart';
import '../workspace_shell/workspace_shell_tabs.dart';
import 'home_workspace_switcher_menu.dart';

/// Whether the mobile drawer trigger should appear in [HomeTitleBar].
@visibleForTesting
bool homeSidebarTriggerVisible({
  required bool isMobile,
  required String? activeTabKey,
}) => isMobile;

/// Height of the Apifox-style workspace title bar.
const double kHomeTitleBarHeight = 58;

/// Vertical padding inside home / workspace tab chips.
const double kHomeTitleBarChipVerticalPadding =
    TpIconButton.kChromeChipVerticalPadding;

/// Hit-target size for title-bar icon controls (⋯ / menu / bell / settings).
///
/// Matches [_HomePill] / [_WorkspaceTab] outer chrome via
/// [TpIconButton.chromeAlignedSize].
double homeTitleBarControlSize(BuildContext context) =>
    TpIconButton.chromeAlignedSize(context);

@visibleForTesting
double homeWorkspaceTabBarAlpha({required bool active, required bool hovered}) {
  if (active) return 1.0;
  if (hovered) return 0.7;
  return 0.4;
}

@visibleForTesting
IconData workspaceTabTopologyIconData(WorkspaceTopology topology) {
  return switch (topology) {
    WorkspaceTopology.local => Icons.folder_outlined,
    WorkspaceTopology.remote => Icons.cloud_outlined,
    WorkspaceTopology.mixed => Icons.hub_outlined,
  };
}

@visibleForTesting
Color homeWorkspaceTabBarColor({
  required ColorScheme colorScheme,
  required Brightness brightness,
  WorkspaceTopology topology = WorkspaceTopology.local,
  required bool active,
  required bool hovered,
}) {
  final base = WorkspaceTopologyColors.of(
    topology: topology,
    colorScheme: colorScheme,
    brightness: brightness,
  );
  return base.withValues(
    alpha: homeWorkspaceTabBarAlpha(active: active, hovered: hovered),
  );
}

@visibleForTesting
Color workspaceTabTopologyIconColor({
  required ColorScheme colorScheme,
  required Brightness brightness,
  WorkspaceTopology topology = WorkspaceTopology.local,
  bool active = false,
  bool hovered = false,
}) {
  final base = WorkspaceTopologyColors.of(
    topology: topology,
    colorScheme: colorScheme,
    brightness: brightness,
  );
  final alpha = active ? 1.0 : (hovered ? 0.9 : 0.8);
  return base.withValues(alpha: alpha);
}

String recentlyClosedEntryLabel(HomeClosedWorkspaceEntry entry) {
  final name = entry.displayName.trim();
  return name.isNotEmpty ? name : entry.workspaceId;
}

String? recentlyClosedSubtitleLine({
  required AppLocalizations l10n,
  required HomeClosedWorkspaceEntry entry,
  required List<HomeClosedWorkspaceEntry> entries,
  required List<LaunchProfile> identities,
}) {
  final path = entry.primaryPath.trim();
  return path.isNotEmpty ? path : null;
}

WorkspaceTopology? recentlyClosedTopology({
  required HomeClosedWorkspaceEntry entry,
  Workspace? workspace,
}) {
  if (workspace != null) {
    return workspaceTopologyOf(workspace.folders);
  }
  return entry.topology;
}

/// Workspace tab glyph colored by topology (local / remote / mixed).
class WorkspaceTabTopologyIcon extends StatelessWidget {
  const WorkspaceTabTopologyIcon({
    required this.topology,
    required this.colorScheme,
    required this.brightness,
    required this.size,
    this.active = false,
    this.hovered = false,
    super.key,
  });

  final WorkspaceTopology topology;
  final ColorScheme colorScheme;
  final Brightness brightness;
  final double size;
  final bool active;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Icon(
      workspaceTabTopologyIconData(topology),
      size: size,
      color: workspaceTabTopologyIconColor(
        colorScheme: colorScheme,
        brightness: brightness,
        topology: topology,
        active: active,
        hovered: hovered,
      ),
    );
  }
}

/// An open workspace tab in the title bar.
class HomeWorkspaceTab {
  const HomeWorkspaceTab({
    required this.id,
    required this.name,
    this.topology = WorkspaceTopology.local,
    this.tooltip,
    this.closable = true,
  });

  final String id;
  final String name;
  final WorkspaceTopology topology;

  /// Shown on hover; defaults to [name] when omitted.
  final String? tooltip;

  /// When false (the pinned personal workspace), no close button is shown.
  final bool closable;
}

class HomeTitleBar extends StatefulWidget {
  const HomeTitleBar({
    this.tabs = const [],
    this.activeTabKey,
    this.pageChrome = WorkspacePageChrome.home,
    this.recentlyClosed = const [],
    this.workspaces = const [],
    this.launchProfiles = const [],
    this.trailingActions,
    this.onHomeTap,
    this.onSelectTab,
    this.onCloseTab,
    this.onCloseAllTabs,
    this.onReopenClosedTab,
    this.onCreateWorkspace,
    super.key,
  });

  /// Open workspace tabs, kept until explicitly closed.
  final List<HomeWorkspaceTab> tabs;

  /// The workspace tab currently shown, or null when the Home view is shown.
  final String? activeTabKey;

  /// Page backdrop chrome; matches [HomeShell] scaffold fill.
  final WorkspacePageChrome pageChrome;

  /// Recently closed tabs (newest first), excluding currently open ids.
  final List<HomeClosedWorkspaceEntry> recentlyClosed;

  /// Workspace records for resolving topology in the recently-closed menu.
  final List<Workspace> workspaces;

  /// Launch identities for personal/team badges in the recently-closed menu.
  final List<LaunchProfile> launchProfiles;

  /// Compact actions on the right (e.g. Run toolbar), before pane toggles.
  final Widget? trailingActions;

  final VoidCallback? onHomeTap;
  final ValueChanged<String>? onSelectTab;
  final ValueChanged<String>? onCloseTab;

  /// Closes every open workspace tab at once.
  final VoidCallback? onCloseAllTabs;
  final ValueChanged<String>? onReopenClosedTab;
  final VoidCallback? onCreateWorkspace;

  @override
  State<HomeTitleBar> createState() => _HomeTitleBarState();
}

class _HomeTitleBarState extends State<HomeTitleBar> with WindowListener {
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
    final sidebarScope = TpSidebarScope.maybeOf(context);
    final isMobile = sidebarScope?.isMobile ?? false;
    final showSidebarTrigger = homeSidebarTriggerVisible(
      isMobile: isMobile,
      activeTabKey: widget.activeTabKey,
    );
    // Compact on all mobile widths — brand + home label + pane toggles overflow
    // phone title bars once UI zoom baseline is 1.0 (logical px, not 1/dpr).
    final compactChrome = isMobile;

    // Paint chrome under the status bar; pad interactive row below it (Android).
    return Material(
      color: cs.workspacePageChrome(widget.pageChrome),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kHomeTitleBarHeight,
          child: Row(
            children: [
              SizedBox(width: compactChrome ? TpMobileChrome.leadingInset : 8),
              if (showWindowControls && useMacWindowChromeStyle)
                _buildWindowControls(),
              if (!compactChrome)
                SizedBox(width: useMacWindowChromeStyle ? 8 : 20),
              if (showSidebarTrigger) ...[
                _HomeTitleBarMobileDrawerTrigger(
                  activeTabKey: widget.activeTabKey,
                ),
                const SizedBox(width: 8),
              ],
              if (!compactChrome) ...[
                const _BrandMark(),
                const SizedBox(width: 24),
              ],
              _HomePill(
                label: compactChrome ? '' : l10n.homeWorkspaceMainWindow,
                active: widget.activeTabKey == null,
                onTap: widget.onHomeTap,
              ),
              if (widget.tabs.isEmpty)
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      HomeWorkspaceSwitcherMenu(
                        openTabs: widget.tabs,
                        activeTabKey: widget.activeTabKey,
                        recentlyClosed: widget.recentlyClosed,
                        workspaces: widget.workspaces,
                        launchProfiles: widget.launchProfiles,
                        onCreate: widget.onCreateWorkspace,
                        onSelectOpen: widget.onSelectTab,
                        onReopenClosed: widget.onReopenClosedTab,
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
                // The open workspace tabs share the remaining width with a single
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
                                    child: _WorkspaceTab(
                                      label: tab.name,
                                      tooltip: tab.tooltip ?? tab.name,
                                      topology: tab.topology,
                                      active: tab.id == widget.activeTabKey,
                                      closable: tab.closable,
                                      onTap: () =>
                                          widget.onSelectTab?.call(tab.id),
                                      onClose: () =>
                                          widget.onCloseTab?.call(tab.id),
                                      onCloseAll: widget.onCloseAllTabs,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Align(
                                  alignment: Alignment.center,
                                  widthFactor: 1,
                                  child: HomeWorkspaceSwitcherMenu(
                                    openTabs: widget.tabs,
                                    activeTabKey: widget.activeTabKey,
                                    recentlyClosed: widget.recentlyClosed,
                                    workspaces: widget.workspaces,
                                    launchProfiles: widget.launchProfiles,
                                    onCreate: widget.onCreateWorkspace,
                                    onSelectOpen: widget.onSelectTab,
                                    onReopenClosed: widget.onReopenClosedTab,
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
              // Mobile: pin bell + settings flush right (panes stay in drawers).
              // Desktop: cap + scale-down so Run/panes/chrome never blow the Row.
              if (compactChrome) ...[
                const SizedBox(width: 8),
                NotificationBellButton(size: homeTitleBarControlSize(context)),
                const SizedBox(width: 4),
                TpIconButton(
                  size: homeTitleBarControlSize(context),
                  iconWidget: SvgPicture.asset(
                    'assets/icons/settings_gear.svg',
                    width: context.tpIconSizes.md,
                    height: context.tpIconSizes.md,
                    theme: SvgTheme(currentColor: cs.onSurfaceVariant),
                  ),
                  tooltip: l10n.settings,
                  backgroundColor: Colors.transparent,
                  onTap: () => showWorkspaceSettingsDialog(context),
                ),
                const SizedBox(width: 16),
              ] else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: double.infinity),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (Platform.isAndroid) ...[
                          const AndroidWorkEnvironmentSelector(),
                          const SizedBox(width: 4),
                        ],
                        if (widget.trailingActions != null) ...[
                          widget.trailingActions!,
                          const SizedBox(width: 8),
                        ],
                        if (widget.activeTabKey != null) ...[
                          const WorkspaceShellPaneVisibilityToggles(),
                          const SizedBox(width: 4),
                        ],
                        const SizedBox(width: 8),
                        NotificationBellButton(
                          size: homeTitleBarControlSize(context),
                        ),
                        TpIconButton(
                          size: homeTitleBarControlSize(context),
                          iconWidget: SvgPicture.asset(
                            'assets/icons/settings_gear.svg',
                            width: context.tpIconSizes.md,
                            height: context.tpIconSizes.md,
                            theme: SvgTheme(currentColor: cs.onSurfaceVariant),
                          ),
                          tooltip: l10n.settings,
                          backgroundColor: Colors.transparent,
                          onTap: () => showWorkspaceSettingsDialog(context),
                        ),
                        const SizedBox(width: 10),
                        if (showWindowControls && !useMacWindowChromeStyle)
                          _buildWindowControls(),
                        const SizedBox(width: 16),
                      ],
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

class _HomeTitleBarMobileDrawerTrigger extends StatelessWidget {
  const _HomeTitleBarMobileDrawerTrigger({required this.activeTabKey});

  final String? activeTabKey;

  @override
  Widget build(BuildContext context) {
    final controlSize = homeTitleBarControlSize(context);
    if (activeTabKey == null) {
      final openMobile = TpSidebarScope.of(context).openMobile;
      return TpSidebarTrigger(size: controlSize, selected: openMobile);
    }

    final composeLanding = context.select<ChatCubit, bool>(
      (c) => c.state.newChatActive,
    );
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (a, b) =>
          a.preferences.sidebarVisible != b.preferences.sidebarVisible ||
          a.narrowLeftSuppressed != b.narrowLeftSuppressed ||
          a.preferences.rightToolsVisible != b.preferences.rightToolsVisible ||
          a.landingRightToolsOverride != b.landingRightToolsOverride,
      builder: (context, layoutState) {
        final open = mobileWorkspaceDrawerOpen(
          layoutState: layoutState,
          composeLanding: composeLanding,
        );
        return TpIconButton(
          icon: open ? Icons.menu_open : Icons.menu,
          size: controlSize,
          selected: open,
          onTap: () {
            final layout = context.read<LayoutCubit>();
            if (open) {
              layout.closeMobileWorkspaceDrawer(composeLanding: composeLanding);
            } else {
              layout.openMobileWorkspaceDrawer(composeLanding: composeLanding);
            }
          },
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [const TeamPilotBrandLogo()],
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
    final styles = TpTextStyles.of(context);
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;
    return TpHover(
      backgroundColor: active
          ? cs.primary.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: active ? cs.primary.withValues(alpha: 0.28) : Colors.transparent,
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: kHomeTitleBarChipVerticalPadding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_filled, size: context.tpIconSizes.md, color: fg),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: styles.smColored(fg)),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    required this.label,
    required this.tooltip,
    this.topology = WorkspaceTopology.local,
    this.active = false,
    this.closable = true,
    this.onTap,
    this.onClose,
    this.onCloseAll,
  });

  final String label;
  final String tooltip;
  final WorkspaceTopology topology;
  final bool active;
  final bool closable;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  /// Closes every open workspace tab at once.
  final VoidCallback? onCloseAll;

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  var _hovered = false;

  /// Touch platforms have no hover; keep tab chrome visible on Android.
  bool get _showChrome => widget.active || _hovered || Platform.isAndroid;

  Future<void> _showTabContextMenuAtGlobal(Offset globalPosition) async {
    if (!widget.closable || widget.onClose == null) return;
    final l10n = context.l10n;
    final selected = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: globalPosition,
      specs: [
        TpActionMenuSpec.item(
          value: 'close',
          icon: Icons.close,
          label: l10n.closeTab,
        ),
        if (widget.onCloseAll != null)
          TpActionMenuSpec.item(
            value: 'closeAll',
            icon: Icons.select_all,
            label: l10n.closeAllTabs,
          ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'close') {
      widget.onClose?.call();
    } else if (selected == 'closeAll') {
      widget.onCloseAll?.call();
    }
  }

  Future<void> _showTabContextMenuAtTap(TapDownDetails details) async {
    await _showTabContextMenuAtGlobal(
      contextMenuGlobalPosition(context, details),
    );
  }

  void _showTabContextMenuFromTap(TapDownDetails details) {
    unawaited(_showTabContextMenuAtTap(details));
  }

  void _showTabContextMenuAtChipCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    unawaited(_showTabContextMenuAtGlobal(center));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final brightness = Theme.of(context).brightness;
    final barColor = homeWorkspaceTabBarColor(
      colorScheme: cs,
      brightness: brightness,
      topology: widget.topology,
      active: active,
      hovered: _hovered,
    );
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: TpHover(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.closable && widget.onClose != null
            ? _showTabContextMenuFromTap
            : null,
        onLongPress:
            widget.closable && widget.onClose != null && Platform.isAndroid
            ? _showTabContextMenuAtChipCenter
            : null,
        onHoverChanged: (hovered) => setState(() => _hovered = hovered),
        borderRadius: BorderRadius.circular(8),
        backgroundColor: active ? cs.surfaceContainerHigh : null,
        hoverColor: active
            ? cs.surfaceContainerHigh
            : cs.onSurface.withValues(alpha: 0.05),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? cs.outlineVariant.withValues(alpha: 0.7)
                    : Colors.transparent,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 10,
                  right: 6,
                  top: kHomeTitleBarChipVerticalPadding,
                  bottom: kHomeTitleBarChipVerticalPadding,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Fixed height: CrossAxisAlignment.stretch would expand
                    // the row to the ListView viewport height (~full title bar).
                    SizedBox(
                      width: 3,
                      height: context.tpIconSizes.md,
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
                      child: WorkspaceTabTopologyIcon(
                        topology: widget.topology,
                        colorScheme: cs,
                        brightness: brightness,
                        size: context.tpIconSizes.md,
                        active: active,
                        hovered: _hovered,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.smColored(fg),
                      ),
                    ),
                    if (widget.closable) ...[
                      const SizedBox(width: 8),
                      _TabChromeSlot(
                        visible: _showChrome,
                        child: TabCloseButton(
                          active: active,
                          onTap: widget.onClose,
                        ),
                      ),
                    ] else
                      const SizedBox(width: 6),
                  ],
                ),
              ),
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
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}
