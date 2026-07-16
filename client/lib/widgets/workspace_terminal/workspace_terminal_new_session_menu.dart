import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

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
import '../menu/sidebar_action_menu.dart';

typedef WorkspaceTerminalSessionSelected =
    void Function(WorkspaceTerminalSessionSpec spec);

/// Shows the workspace shell launch catalog at [globalPosition] (Orca-style +).
///
/// Uses [showSidebarActionMenuFromSpecs] (root overlay) so PTY-driven rebuilds
/// cannot tear down an anchored popover mid-stream.
Future<void> showWorkspaceTerminalLaunchMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<WorkspaceFolder> folders,
  required WorkspaceShellConnector connector,
  required WorkspaceTerminalSessionSelected onSessionSelected,
}) async {
  final items = await WorkspaceTerminalLaunchCatalog.build(
    folders: folders,
    sshProfiles: context.read<SshProfileRepository>(),
    connector: connector,
  );
  if (!context.mounted) return;

  final selected =
      await showSidebarActionMenuFromSpecs<WorkspaceTerminalLaunchMenuItem>(
        context: context,
        globalPosition: globalPosition,
        specs: _launchMenuSpecs(context, items),
      );
  if (!context.mounted || selected == null) return;
  await _handleLaunchMenuSelection(
    context: context,
    selected: selected,
    onSessionSelected: onSessionSelected,
  );
}

List<SidebarActionMenuSpec> _launchMenuSpecs(
  BuildContext context,
  List<WorkspaceTerminalLaunchMenuItem> items,
) {
  final l10n = context.l10n;
  final specs = <SidebarActionMenuSpec>[];
  for (final item in items) {
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

Future<void> _handleLaunchMenuSelection({
  required BuildContext context,
  required WorkspaceTerminalLaunchMenuItem selected,
  required WorkspaceTerminalSessionSelected onSessionSelected,
}) async {
  switch (selected.action) {
    case WorkspaceTerminalLaunchAction.openSession:
      final spec = selected.spec;
      if (spec != null) onSessionSelected(spec);
    case WorkspaceTerminalLaunchAction.newSshProfile:
      await showSshProfileFormDialog(context);
    case WorkspaceTerminalLaunchAction.settings:
      if (!context.mounted) return;
      await showWorkspaceTerminalSettingsSheet(context);
  }
}

/// Theme sheet for workspace shell (also reachable from the + catalog).
Future<void> showWorkspaceTerminalSettingsSheet(BuildContext context) async {
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
                    style: TpTextStyles.of(context).mdSemiboldTightSnug,
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
