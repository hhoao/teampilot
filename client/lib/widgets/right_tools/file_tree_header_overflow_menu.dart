import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/app_localizations.dart';
import '../app_icon_button.dart';
import '../menu/sidebar_action_menu.dart';

enum FileTreeHeaderAction { reveal, toggleHidden, copy }

/// Compact header overflow menu when the file-tree panel is too narrow for
/// inline action buttons.
class FileTreeHeaderOverflowMenu extends StatelessWidget {
  const FileTreeHeaderOverflowMenu({
    required this.l10n,
    required this.showHiddenFiles,
    required this.canCopy,
    required this.onReveal,
    required this.onToggleHidden,
    required this.onCopy,
    super.key,
  });

  final AppLocalizations l10n;
  final bool showHiddenFiles;
  final bool canCopy;
  final VoidCallback onReveal;
  final VoidCallback onToggleHidden;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SidebarActionMenuButton(
      tooltip: l10n.fileTree,
      icon: Icon(Icons.more_vert, size: context.appIconSizes.sm),
      size: AppIconButton.kCompactSize,
      specs: [
        SidebarActionMenuSpec.item(
          value: FileTreeHeaderAction.reveal,
          icon: Icons.my_location_outlined,
          label: l10n.fileTreeRevealActiveFile,
        ),
        SidebarActionMenuSpec.item(
          value: FileTreeHeaderAction.toggleHidden,
          icon: showHiddenFiles
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
        ),
        SidebarActionMenuSpec.item(
          value: FileTreeHeaderAction.copy,
          icon: Icons.copy,
          label: l10n.copy,
          enabled: canCopy,
        ),
      ],
      onSelected: (action) {
        switch (action as FileTreeHeaderAction) {
          case FileTreeHeaderAction.reveal:
            onReveal();
          case FileTreeHeaderAction.toggleHidden:
            onToggleHidden();
          case FileTreeHeaderAction.copy:
            onCopy();
        }
      },
    );
  }
}
