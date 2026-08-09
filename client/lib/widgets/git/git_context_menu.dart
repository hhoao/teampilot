import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Right-click menu for a changed-file row in the source control tree.
abstract final class GitFileContextMenu {
  static Future<void> show({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required bool staged,
    required String path,
    required VoidCallback? onOpenFile,
    required VoidCallback onOpenDiff,
    required VoidCallback onStage,
    required VoidCallback onUnstage,
    required VoidCallback onDiscard,
  }) async {
    final l10n = context.l10n;
    final specs = <TpActionMenuSpec>[
      if (onOpenFile != null)
        TpActionMenuSpec.item(
          value: 'open',
          icon: Icons.file_open_outlined,
          label: l10n.gitOpenFile,
        ),
      TpActionMenuSpec.item(
        value: 'diff',
        icon: Icons.difference_outlined,
        label: l10n.gitShowDiff,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: staged ? 'unstage' : 'stage',
        icon: staged ? Icons.remove : Icons.add,
        label: staged ? l10n.gitUnstage : l10n.gitStage,
      ),
      TpActionMenuSpec.item(
        value: 'discard',
        icon: Icons.undo,
        label: l10n.gitDiscard,
        destructive: true,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.gitCopyPath,
      ),
    ];
    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'open':
        onOpenFile!();
      case 'diff':
        onOpenDiff();
      case 'stage':
        onStage();
      case 'unstage':
        onUnstage();
      case 'discard':
        onDiscard();
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: path));
    }
  }
}

/// Right-click menu for a folder row in the source control tree.
abstract final class GitFolderContextMenu {
  static Future<void> show({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required String folderPath,
    required VoidCallback onStage,
    required VoidCallback onUnstage,
    required VoidCallback onDiscardFolder,
  }) async {
    final l10n = context.l10n;
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: 'stage',
        icon: Icons.add,
        label: l10n.gitStageFolder,
      ),
      TpActionMenuSpec.item(
        value: 'unstage',
        icon: Icons.remove,
        label: l10n.gitUnstageFolder,
      ),
      TpActionMenuSpec.item(
        value: 'discard',
        icon: Icons.undo,
        label: l10n.gitDiscardFolder,
        destructive: true,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.gitCopyPath,
      ),
    ];
    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'stage':
        onStage();
      case 'unstage':
        onUnstage();
      case 'discard':
        onDiscardFolder();
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: folderPath));
    }
  }
}
