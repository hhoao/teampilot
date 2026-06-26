import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace_folder.dart';
import '../../pages/workspace_shell/workspace_shell_tabs.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_title_resolver.dart';
import '../app_icon_button.dart';
import 'workspace_terminal_new_session_menu.dart';

/// Horizontal tab strip above the workspace terminal — matches [WorkspaceShellTabRow].
class WorkspaceTerminalTabBar extends StatelessWidget {
  const WorkspaceTerminalTabBar({
    required this.entries,
    required this.activeEntryId,
    required this.onSelect,
    required this.onCloseEntry,
    required this.onQuickNew,
    required this.folders,
    required this.connector,
    required this.onSessionSelected,
    required this.onClosePanel,
    super.key,
  });

  final List<WorkspaceTerminalEntry> entries;
  final String? activeEntryId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCloseEntry;
  final VoidCallback onQuickNew;
  final List<WorkspaceFolder> folders;
  final WorkspaceShellConnector connector;
  final WorkspaceTerminalSessionSelected onSessionSelected;
  final VoidCallback onClosePanel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in entries)
                    WorkspaceShellTabChip(
                      key: ValueKey(entry.id),
                      title: _entryTitle(entry),
                      active: entry.id == activeEntryId,
                      onTap: () => onSelect(entry.id),
                      onClose: () => onCloseEntry(entry.id),
                      accentColor: cs.primary,
                    ),
                ],
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.add,
            color: muted,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalNewSession,
            onTap: onQuickNew,
          ),
          WorkspaceTerminalNewSessionMenuButton(
            folders: folders,
            connector: connector,
            iconColor: muted,
            onSessionSelected: onSessionSelected,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            color: muted,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalHide,
            onTap: onClosePanel,
          ),
        ],
      ),
    );
  }

  String _entryTitle(WorkspaceTerminalEntry entry) {
    final baseLabel = entry.titleLabel.isEmpty ? '…' : entry.titleLabel;
    return WorkspaceTerminalTitleResolver.tabTitle(
      entry: entry,
      siblings: entries,
      baseLabel: baseLabel,
    );
  }
}
