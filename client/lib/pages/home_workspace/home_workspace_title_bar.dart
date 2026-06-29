import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../models/launch_profile.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../services/app/desktop_window_actions.dart';
import '../../services/app/platform_utils.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../theme/workspace_topology_colors.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/notification/notification_bell_button.dart';
import '../../utils/context_menu_position.dart';
import '../../widgets/team_pilot_brand_logo.dart';
import '../../widgets/window_chrome_controls.dart';
import '../../widgets/window_drag_area.dart';
import '../config/config_workspace.dart';
import 'open_workspace_tab_actions.dart';

/// Height of the Apifox-style workspace title bar.
const double kHomeTitleBarHeight = 58;

/// Custom window title bar for the new workspace home: brand mark, a "Home"
/// pill, optional open-workspace tab, decorative action glyphs, and the real
/// minimize/maximize/close controls. Reuses theme tokens only — no hardcoded
/// brand colors.
/// Personal vs team discriminator for title-bar workspace tabs.
enum HomeWorkspaceTabKind { personal, team }

@visibleForTesting
double homeWorkspaceTabBarAlpha({required bool active, required bool hovered}) {
  if (active) return 1.0;
  if (hovered) return 0.7;
  return 0.4;
}

/// Hue-rotated complement of [base] on the color wheel (反色系).
@visibleForTesting
Color homeWorkspaceTabComplementColor(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withHue((hsl.hue + 180) % 360).toColor();
}

@visibleForTesting
Color homeWorkspaceTabKindAccentColor({
  required HomeWorkspaceTabKind kind,
  required ColorScheme colorScheme,
}) {
  final personal = colorScheme.primary;
  return kind == HomeWorkspaceTabKind.personal
      ? personal
      : homeWorkspaceTabComplementColor(personal);
}

@visibleForTesting
IconData homeWorkspaceTabKindIcon(HomeWorkspaceTabKind kind) {
  return switch (kind) {
    HomeWorkspaceTabKind.personal => Icons.person_outline_rounded,
    HomeWorkspaceTabKind.team => Icons.groups_2_outlined,
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

@visibleForTesting
Color homeWorkspaceTabKindIconColor({
  required HomeWorkspaceTabKind kind,
  required ColorScheme colorScheme,
  required bool active,
  required bool hovered,
}) {
  final base = homeWorkspaceTabKindAccentColor(
    kind: kind,
    colorScheme: colorScheme,
  );
  // Keep kind readable on inactive tabs; bar alone was too subtle on warm presets.
  final alpha = active ? 1.0 : (hovered ? 0.9 : 0.8);
  return base.withValues(alpha: alpha);
}

@visibleForTesting
String recentlyClosedEntryLabel(HomeClosedWorkspaceEntry entry) {
  final name = entry.displayName.trim();
  return name.isNotEmpty ? name : entry.workspaceId;
}

@visibleForTesting
bool recentlyClosedShowIdentityInSubtitle({
  required HomeClosedWorkspaceEntry entry,
  required List<HomeClosedWorkspaceEntry> entries,
  required List<LaunchProfile> identities,
}) {
  final duplicateDirectory = entries
          .where((candidate) => candidate.workspaceId == entry.workspaceId)
          .length >
      1;
  if (duplicateDirectory) return true;
  final profile =
      identities.where((e) => e.id == entry.identity.profileId).firstOrNull ??
      identities
          .where((e) => e.id == LaunchProfileProvisioner.defaultPersonalId)
          .firstOrNull;
  return profile?.kind == LaunchProfileKind.team;
}

HomeWorkspaceTabKind workspaceTabKindForIdentity({
  required LaunchProfileRef identity,
  required List<LaunchProfile> identities,
}) {
  final profile =
      identities.where((e) => e.id == identity.profileId).firstOrNull ??
      identities
          .where((e) => e.id == LaunchProfileProvisioner.defaultPersonalId)
          .firstOrNull;
  return profile?.kind == LaunchProfileKind.team
      ? HomeWorkspaceTabKind.team
      : HomeWorkspaceTabKind.personal;
}

@visibleForTesting
HomeWorkspaceTabKind recentlyClosedTabKind({
  required LaunchProfileRef identity,
  required List<LaunchProfile> identities,
}) =>
    workspaceTabKindForIdentity(identity: identity, identities: identities);

@visibleForTesting
String recentlyClosedIdentityLabel({
  required AppLocalizations l10n,
  required HomeClosedWorkspaceEntry entry,
  required List<LaunchProfile> identities,
}) =>
    workspaceTabIdentityLabel(
      l10n: l10n,
      identity: entry.identity,
      identities: identities,
    );

@visibleForTesting
String? recentlyClosedSubtitleLine({
  required AppLocalizations l10n,
  required HomeClosedWorkspaceEntry entry,
  required List<HomeClosedWorkspaceEntry> entries,
  required List<LaunchProfile> identities,
}) {
  final path = entry.primaryPath.trim();
  final showIdentity = recentlyClosedShowIdentityInSubtitle(
    entry: entry,
    entries: entries,
    identities: identities,
  );
  final identityPart = showIdentity
      ? recentlyClosedIdentityLabel(
          l10n: l10n,
          entry: entry,
          identities: identities,
        )
      : null;
  if (identityPart != null && path.isNotEmpty) {
    return '$identityPart · $path';
  }
  if (path.isNotEmpty) return path;
  return identityPart;
}

@visibleForTesting
WorkspaceTopology? recentlyClosedTopology({
  required HomeClosedWorkspaceEntry entry,
  Workspace? workspace,
}) {
  if (workspace != null) {
    return workspaceTopologyOf(workspace.folders);
  }
  return entry.topology;
}

/// Personal/team glyph colored by workspace topology (local / remote / mixed).
class WorkspaceTabKindTopologyIcon extends StatelessWidget {
  const WorkspaceTabKindTopologyIcon({
    required this.kind,
    required this.topology,
    required this.colorScheme,
    required this.brightness,
    required this.size,
    this.active = false,
    this.hovered = false,
    super.key,
  });

  final HomeWorkspaceTabKind kind;
  final WorkspaceTopology topology;
  final ColorScheme colorScheme;
  final Brightness brightness;
  final double size;
  final bool active;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Icon(
      homeWorkspaceTabKindIcon(kind),
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
    required this.kind,
    this.topology = WorkspaceTopology.local,
    this.tooltip,
    this.closable = true,
  });

  final String id;
  final String name;
  final HomeWorkspaceTabKind kind;
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
    this.onHomeTap,
    this.onSelectTab,
    this.onCloseTab,
    this.onReopenClosedTab,
    this.onOpenTabWithOtherIdentity,
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
  final VoidCallback? onHomeTap;
  final ValueChanged<String>? onSelectTab;
  final ValueChanged<String>? onCloseTab;
  final ValueChanged<String>? onReopenClosedTab;
  final ValueChanged<String>? onOpenTabWithOtherIdentity;

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
              active: widget.activeTabKey == null,
              onTap: widget.onHomeTap,
            ),
            if (widget.tabs.isEmpty)
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    _RecentlyClosedOverflowButton(
                      entries: widget.recentlyClosed,
                      workspaces: widget.workspaces,
                      launchProfiles: widget.launchProfiles,
                      onReopen: widget.onReopenClosedTab,
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
                                    kind: tab.kind,
                                    topology: tab.topology,
                                    active: tab.id == widget.activeTabKey,
                                    closable: tab.closable,
                                    onTap: () =>
                                        widget.onSelectTab?.call(tab.id),
                                    onClose: () =>
                                        widget.onCloseTab?.call(tab.id),
                                    onOpenWithOtherIdentity: () => widget
                                        .onOpenTabWithOtherIdentity
                                        ?.call(tab.id),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Align(
                                alignment: Alignment.center,
                                widthFactor: 1,
                                child: _RecentlyClosedOverflowButton(
                                  entries: widget.recentlyClosed,
                                  workspaces: widget.workspaces,
                                  launchProfiles: widget.launchProfiles,
                                  onReopen: widget.onReopenClosedTab,
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

class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    required this.label,
    required this.tooltip,
    required this.kind,
    this.topology = WorkspaceTopology.local,
    this.active = false,
    this.closable = true,
    this.onTap,
    this.onClose,
    this.onOpenWithOtherIdentity,
  });

  final String label;
  final String tooltip;
  final HomeWorkspaceTabKind kind;
  final WorkspaceTopology topology;
  final bool active;
  final bool closable;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onOpenWithOtherIdentity;

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  var _hovered = false;

  /// Touch platforms have no hover; keep tab chrome visible on Android.
  bool get _showChrome => widget.active || _hovered || Platform.isAndroid;

  Future<void> _showTabContextMenuAtGlobal(Offset globalPosition) async {
    if (widget.onOpenWithOtherIdentity == null) return;
    final l10n = context.l10n;
    final selected = await showSidebarActionMenuFromSpecs<String>(
      context: context,
      globalPosition: globalPosition,
      specs: [
        SidebarActionMenuSpec.item(
          value: 'otherIdentity',
          icon: Icons.badge_outlined,
          label: l10n.homeWorkspaceOpenInNewTabWithOtherIdentity,
        ),
        if (widget.closable && widget.onClose != null)
          SidebarActionMenuSpec.item(
            value: 'close',
            icon: Icons.close,
            label: l10n.closeTab,
          ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'otherIdentity':
        widget.onOpenWithOtherIdentity?.call();
      case 'close':
        widget.onClose?.call();
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
    final styles = AppTextStyles.of(context);
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onOpenWithOtherIdentity == null
              ? null
              : _showTabContextMenuFromTap,
          onLongPress: widget.onOpenWithOtherIdentity == null || !Platform.isAndroid
              ? null
              : _showTabContextMenuAtChipCenter,
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
                  child: WorkspaceTabKindTopologyIcon(
                    kind: widget.kind,
                    topology: widget.topology,
                    colorScheme: cs,
                    brightness: brightness,
                    size: context.appIconSizes.md,
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

/// Overflow menu listing recently closed workspace tabs; opens on hover.
class _RecentlyClosedOverflowButton extends StatefulWidget {
  const _RecentlyClosedOverflowButton({
    required this.entries,
    this.workspaces = const [],
    this.launchProfiles = const [],
    this.onReopen,
  });

  final List<HomeClosedWorkspaceEntry> entries;
  final List<Workspace> workspaces;
  final List<LaunchProfile> launchProfiles;
  final ValueChanged<String>? onReopen;

  static const _menuMaxHeight = 320.0;
  static const _menuWidth = 300.0;
  static const _closeDelay = Duration(milliseconds: 180);

  @override
  State<_RecentlyClosedOverflowButton> createState() =>
      _RecentlyClosedOverflowButtonState();
}

class _RecentlyClosedOverflowButtonState
    extends State<_RecentlyClosedOverflowButton> {
  final _popoverController = AppPopoverController();
  Timer? _closeTimer;
  var _pointerOnAnchor = false;
  var _pointerOnMenu = false;

  ActionMenuController get _menuController =>
      ActionMenuController(_popoverController);

  @override
  void dispose() {
    _closeTimer?.cancel();
    _popoverController.dispose();
    super.dispose();
  }

  void _cancelCloseTimer() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void _scheduleClose() {
    _cancelCloseTimer();
    _closeTimer = Timer(_RecentlyClosedOverflowButton._closeDelay, () {
      if (!_pointerOnAnchor && !_pointerOnMenu && _popoverController.isOpen) {
        _popoverController.hide();
      }
    });
  }

  void _openMenu() {
    _cancelCloseTimer();
    if (!_popoverController.isOpen) {
      _popoverController.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final entries = [
      for (final entry in widget.entries)
        if (entry.workspaceId.trim().isNotEmpty) entry,
    ];
    final workspaceById = {
      for (final workspace in widget.workspaces)
        workspace.workspaceId: workspace,
    };
    final identities = widget.launchProfiles;

    return ActionMenuPopoverAnchor(
      controller: _popoverController,
      minWidth: _RecentlyClosedOverflowButton._menuWidth,
      fixedPanelWidth: _RecentlyClosedOverflowButton._menuWidth,
      onOpen: _cancelCloseTimer,
      popoverBuilder: (context, controller) => MouseRegion(
        onEnter: (_) {
          _pointerOnMenu = true;
          _cancelCloseTimer();
        },
        onExit: (_) {
          _pointerOnMenu = false;
          _scheduleClose();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0)
                          const SizedBox(
                            height: SidebarActionMenuMetrics.itemGap,
                          ),
                        _RecentlyClosedMenuItem(
                          entry: entries[i],
                          entries: entries,
                          workspace: workspaceById[entries[i].workspaceId],
                          identities: identities,
                          menuController: _menuController,
                          onReopen: widget.onReopen,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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

class _RecentlyClosedMenuItem extends StatelessWidget {
  const _RecentlyClosedMenuItem({
    required this.entry,
    required this.entries,
    required this.workspace,
    required this.identities,
    required this.menuController,
    this.onReopen,
  });

  final HomeClosedWorkspaceEntry entry;
  final List<HomeClosedWorkspaceEntry> entries;
  final Workspace? workspace;
  final List<LaunchProfile> identities;
  final ActionMenuController menuController;
  final ValueChanged<String>? onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final kind = workspaceTabKindForIdentity(
      identity: entry.identity,
      identities: identities,
    );
    final subtitle = recentlyClosedSubtitleLine(
      l10n: l10n,
      entry: entry,
      entries: entries,
      identities: identities,
    );
    final topology = recentlyClosedTopology(entry: entry, workspace: workspace);
    final brightness = Theme.of(context).brightness;

    return SidebarActionMenuItem(
      iconWidget: WorkspaceTabKindTopologyIcon(
        kind: kind,
        topology: topology ?? WorkspaceTopology.local,
        colorScheme: cs,
        brightness: brightness,
        size: SidebarActionMenuMetrics.iconSize(context),
      ),
      label: recentlyClosedEntryLabel(entry),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.caption.copyWith(color: cs.onSurfaceVariant),
            ),
      menuController: menuController,
      onTap: () => onReopen?.call(entry.tabKey),
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
