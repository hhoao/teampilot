import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import 'home_workspace_title_bar.dart';

/// Whether the open-tabs section should appear in [HomeWorkspaceSwitcherMenu].
@visibleForTesting
bool homeWorkspaceSwitcherShouldShowOpenSection(List<HomeWorkspaceTab> openTabs) =>
    openTabs.isNotEmpty;

/// Title-bar ⋯ menu: create workspace, jump to open tabs, reopen recently closed.
class HomeWorkspaceSwitcherMenu extends StatefulWidget {
  const HomeWorkspaceSwitcherMenu({
    required this.openTabs,
    this.activeTabKey,
    this.recentlyClosed = const [],
    this.workspaces = const [],
    this.launchProfiles = const [],
    this.onCreate,
    this.onSelectOpen,
    this.onReopenClosed,
    super.key,
  });

  final List<HomeWorkspaceTab> openTabs;
  final String? activeTabKey;
  final List<HomeClosedWorkspaceEntry> recentlyClosed;
  final List<Workspace> workspaces;
  final List<LaunchProfile> launchProfiles;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onSelectOpen;
  final ValueChanged<String>? onReopenClosed;

  static const _menuMaxHeight = 320.0;
  static const _menuWidth = 300.0;
  static const _closeDelay = Duration(milliseconds: 180);

  @override
  State<HomeWorkspaceSwitcherMenu> createState() =>
      _HomeWorkspaceSwitcherMenuState();
}

class _HomeWorkspaceSwitcherMenuState extends State<HomeWorkspaceSwitcherMenu> {
  final _popoverController = TpPopoverController();
  Timer? _closeTimer;
  var _pointerOnAnchor = false;
  var _pointerOnMenu = false;

  TpActionMenuController get _menuController =>
      TpActionMenuController(_popoverController);

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
    _closeTimer = Timer(HomeWorkspaceSwitcherMenu._closeDelay, () {
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

  void _toggleMenu() {
    _cancelCloseTimer();
    if (_popoverController.isOpen) {
      _popoverController.hide();
    } else {
      _popoverController.show();
    }
  }

  void _onCreateTap() {
    _popoverController.hide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCreate?.call();
    });
  }

  Widget _openTabItem({
    required HomeWorkspaceTab tab,
    required ColorScheme colorScheme,
    required Brightness brightness,
    required double iconSize,
  }) {
    final active = tab.id == widget.activeTabKey;
    return TpActionMenuItem(
      iconWidget: WorkspaceTabTopologyIcon(
        topology: tab.topology,
        colorScheme: colorScheme,
        brightness: brightness,
        size: iconSize,
        active: active,
      ),
      label: tab.name,
      trailing: active
          ? Icon(Icons.check, size: iconSize, color: colorScheme.primary)
          : null,
      menuController: _menuController,
      onTap: () => widget.onSelectOpen?.call(tab.id),
    );
  }

  Widget _sectionHeader(String label, ColorScheme cs, TpTextStyles styles) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        label,
        style: styles.smSemiboldColored(cs.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final showOpen = homeWorkspaceSwitcherShouldShowOpenSection(widget.openTabs);
    final closedEntries = [
      for (final entry in widget.recentlyClosed)
        if (entry.workspaceId.trim().isNotEmpty) entry,
    ];
    final workspaceById = {
      for (final workspace in widget.workspaces)
        workspace.workspaceId: workspace,
    };
    final identities = widget.launchProfiles;
    final iconSize = TpActionMenuMetrics.iconSize(context);

    return TpActionMenuAnchor(
      controller: _popoverController,
      minWidth: HomeWorkspaceSwitcherMenu._menuWidth,
      fixedPanelWidth: HomeWorkspaceSwitcherMenu._menuWidth,
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
            TpActionMenuItem(
              icon: Icons.add,
              label: l10n.newWorkspace,
              menuController: _menuController,
              onTap: _onCreateTap,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: HomeWorkspaceSwitcherMenu._menuMaxHeight,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showOpen) ...[
                      const SizedBox(height: TpActionMenuMetrics.itemGap),
                      _sectionHeader(l10n.homeWorkspaceOpenTabs, cs, styles),
                      for (var i = 0; i < widget.openTabs.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: TpActionMenuMetrics.itemGap),
                        _openTabItem(
                          tab: widget.openTabs[i],
                          colorScheme: cs,
                          brightness: brightness,
                          iconSize: iconSize,
                        ),
                      ],
                    ],
                    const SizedBox(height: TpActionMenuMetrics.itemGap),
                    _sectionHeader(
                      l10n.homeWorkspaceRecentlyClosed,
                      cs,
                      styles,
                    ),
                    if (closedEntries.isEmpty)
                      TpActionMenuItem(
                        icon: Icons.inbox_outlined,
                        label: l10n.homeWorkspaceRecentlyClosedEmpty,
                        enabled: false,
                        menuController: _menuController,
                      )
                    else
                      for (var i = 0; i < closedEntries.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: TpActionMenuMetrics.itemGap),
                        _ClosedWorkspaceMenuItem(
                          entry: closedEntries[i],
                          entries: closedEntries,
                          workspace:
                              workspaceById[closedEntries[i].workspaceId],
                          identities: identities,
                          menuController: _menuController,
                          onReopen: widget.onReopenClosed,
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
        child: TpIconButton(
          icon: Icons.more_horiz,
          tooltip: l10n.homeWorkspaceRecentlyClosed,
          color: cs.onSurfaceVariant,
          backgroundColor: Colors.transparent,
          onTap: _toggleMenu,
        ),
      ),
    );
  }
}

class _ClosedWorkspaceMenuItem extends StatelessWidget {
  const _ClosedWorkspaceMenuItem({
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
  final TpActionMenuController menuController;
  final ValueChanged<String>? onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final subtitle = recentlyClosedSubtitleLine(
      l10n: l10n,
      entry: entry,
      entries: entries,
      identities: identities,
    );
    final topology = recentlyClosedTopology(entry: entry, workspace: workspace);
    final brightness = Theme.of(context).brightness;

    return TpActionMenuItem(
      iconWidget: WorkspaceTabTopologyIcon(
        topology: topology ?? WorkspaceTopology.local,
        colorScheme: cs,
        brightness: brightness,
        size: TpActionMenuMetrics.iconSize(context),
      ),
      label: recentlyClosedEntryLabel(entry),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.xsColored(cs.onSurfaceVariant),
            ),
      menuController: menuController,
      onTap: () => onReopen?.call(entry.tabKey),
    );
  }
}
