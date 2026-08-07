import 'package:flutter/material.dart';

import '../../../cubits/workbench/workbench_tab.dart';
import '../../../l10n/app_localizations.dart';
import '../../storage/runtime_context.dart';

/// Inputs for building workbench tab context menu items at show-time.
class WorkbenchTabMenuContext {
  const WorkbenchTabMenuContext({
    required this.l10n,
    this.buildContext,
    required this.kind,
    required this.tabId,
    this.filePath,
    this.workspaceRoot,
    required this.pinnable,
    required this.pinned,
    required this.desktopShellActions,
    required this.remoteFileManagerActions,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseRight,
    this.onCloseAll,
    this.onPin,
    this.workContext,
  });

  final AppLocalizations l10n;

  /// For toast / mounted checks; nullable in composer unit tests.
  final BuildContext? buildContext;

  final WorkbenchTabKind kind;
  final String tabId;

  /// File tab id, or diff absolute path when known.
  final String? filePath;

  /// Workspace folder root for relative path copy.
  final String? workspaceRoot;

  final bool pinnable;
  final bool pinned;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;

  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;

  /// Closes every tab in the workspace's strip.
  final VoidCallback? onCloseAll;
  final VoidCallback? onPin;

  final RuntimeContext? workContext;
}
