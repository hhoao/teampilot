import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../pages/ssh_profiles/ssh_profile_form_dialog.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_launch_catalog.dart';
import '../app_icon_button.dart';
import '../menu/sidebar_action_menu.dart';

typedef WorkspaceTerminalSessionSelected =
    void Function(WorkspaceTerminalSessionSpec spec);

/// IDEA-style “▾” menu: local shells first, full catalog after refresh.
///
/// Uses [showSidebarActionMenuFromSpecs] (root overlay + global anchor) instead
/// of [SidebarActionMenuIconAnchor] — the terminal panel rebuilds often while
/// PTY output streams, which breaks anchored [AppPopover] overlays.
class WorkspaceTerminalNewSessionMenuButton extends StatefulWidget {
  const WorkspaceTerminalNewSessionMenuButton({
    required this.folders,
    required this.connector,
    required this.onSessionSelected,
    required this.iconColor,
    super.key,
  });

  final List<WorkspaceFolder> folders;
  final WorkspaceShellConnector connector;
  final WorkspaceTerminalSessionSelected onSessionSelected;
  final Color iconColor;

  @override
  State<WorkspaceTerminalNewSessionMenuButton> createState() =>
      _WorkspaceTerminalNewSessionMenuButtonState();
}

class _WorkspaceTerminalNewSessionMenuButtonState
    extends State<WorkspaceTerminalNewSessionMenuButton> {
  final _anchorKey = GlobalKey();

  var _items = WorkspaceTerminalLaunchCatalog.buildLocalShells();
  var _refreshGeneration = 0;
  var _menuOpen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshItems());
  }

  @override
  void didUpdateWidget(covariant WorkspaceTerminalNewSessionMenuButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.folders, widget.folders)) {
      _items = WorkspaceTerminalLaunchCatalog.buildLocalShells();
      unawaited(_refreshItems());
    }
  }

  Future<void> _refreshItems() async {
    final generation = ++_refreshGeneration;
    final items = await WorkspaceTerminalLaunchCatalog.build(
      folders: widget.folders,
      sshProfiles: context.read<SshProfileRepository>(),
      connector: widget.connector,
    );
    if (!mounted || generation != _refreshGeneration) return;
    setState(() => _items = items);
  }

  List<SidebarActionMenuSpec> _specs(BuildContext context) {
    final l10n = context.l10n;
    final specs = <SidebarActionMenuSpec>[];
    for (final item in _items) {
      if (item.isDivider) {
        specs.add(const SidebarActionMenuSpec.divider());
        continue;
      }
      switch (item.action) {
        case WorkspaceTerminalLaunchAction.openSession:
          specs.add(
            SidebarActionMenuSpec.item(
              value: item,
              label: item.label,
              icon: Icons.terminal,
            ),
          );
        case WorkspaceTerminalLaunchAction.newSshProfile:
          specs.add(
            SidebarActionMenuSpec.item(
              value: item,
              label: l10n.workspaceTerminalNewSshSession,
              icon: Icons.add_link,
            ),
          );
        case WorkspaceTerminalLaunchAction.settings:
          specs.add(
            SidebarActionMenuSpec.item(
              value: item,
              label: l10n.workspaceTerminalSettings,
              icon: Icons.settings_outlined,
            ),
          );
      }
    }
    return specs;
  }

  Future<void> _showMenu() async {
    if (_menuOpen) return;
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final anchor = box.localToGlobal(
      box.size.bottomLeft(Offset.zero),
    );

    setState(() => _menuOpen = true);
    unawaited(_refreshItems());

    final selected =
        await showSidebarActionMenuFromSpecs<WorkspaceTerminalLaunchMenuItem>(
          context: context,
          globalPosition: anchor + const Offset(0, 4),
          specs: _specs(context),
        );

    if (!mounted) return;
    setState(() => _menuOpen = false);

    if (selected == null) return;
    await _handleSelected(context, selected);
  }

  Future<void> _handleSelected(
    BuildContext context,
    WorkspaceTerminalLaunchMenuItem selected,
  ) async {
    switch (selected.action) {
      case WorkspaceTerminalLaunchAction.openSession:
        final spec = selected.spec;
        if (spec != null) widget.onSessionSelected(spec);
      case WorkspaceTerminalLaunchAction.newSshProfile:
        await showSshProfileFormDialog(context);
        if (!context.mounted) return;
        unawaited(_refreshItems());
      case WorkspaceTerminalLaunchAction.settings:
        if (!context.mounted) return;
        await _showTerminalSettingsSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KeyedSubtree(
      key: _anchorKey,
      child: AppIconButton(
        icon: Icons.arrow_drop_down,
        color: widget.iconColor,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.workspaceTerminalNewSessionMenu,
        onTap: () => unawaited(_showMenu()),
      ),
    );
  }
}

Future<void> _showTerminalSettingsSheet(BuildContext context) async {
  final l10n = context.l10n;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return BlocBuilder<LayoutCubit, LayoutState>(
        builder: (context, state) {
          final mode = state.preferences.terminalThemeMode;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.workspaceTerminalSettings,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'adaptive',
                        label: Text(l10n.workspaceTerminalThemeAdaptive),
                      ),
                      ButtonSegment(
                        value: 'classicDark',
                        label: Text(l10n.workspaceTerminalThemeClassicDark),
                      ),
                      ButtonSegment(
                        value: 'highContrast',
                        label: Text(l10n.workspaceTerminalThemeHighContrast),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (selection) {
                      final value = selection.firstOrNull;
                      if (value == null) return;
                      context.read<LayoutCubit>().setTerminalThemeMode(value);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
