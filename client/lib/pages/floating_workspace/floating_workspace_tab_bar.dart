import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/floating_workspace_tab.dart';
import '../../services/io/file_path_actions.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../workspace_shell/workspace_shell_tabs.dart';
import 'floating_workspace_new_terminal_menu.dart';

(WorkbenchTabKind kind, String? filePath) floatingTabMenuIdentity(
  FloatingTab tab,
) {
  return switch (tab.surfaceId) {
    'filePreview' => (
      WorkbenchTabKind.file,
      tab.payload is String ? tab.payload as String : null,
    ),
    'diffPreview' => () {
      final key = tab.payload is String ? tab.payload as String : null;
      final parsed = key == null ? null : WorkbenchTabId.parseDiffKey(key);
      return (WorkbenchTabKind.diff, parsed?.$1);
    }(),
    'terminal' => (WorkbenchTabKind.shell, null),
    _ => (WorkbenchTabKind.run, null),
  };
}

bool _desktopShellActionsFor(RuntimeContext? workContext) {
  if (workContext == null || kIsWeb) return false;
  return workContext.mode == StorageBackendMode.native ||
      workContext.mode == StorageBackendMode.wsl;
}

bool _remoteFileManagerActionsFor(RuntimeContext? workContext) {
  if (workContext == null || kIsWeb) return false;
  return workContext.mode == StorageBackendMode.ssh;
}

/// Tabs-only strip for the floating title bar.
///
/// The "+" control is a sibling outside this scroll viewport (Orca-style): the
/// strip shrink-wraps when tabs fit so "+" sits after the last tab; when the
/// strip hits its max width it scrolls and "+" stays just after the strip.
class FloatingWorkspaceTabBar extends StatelessWidget {
  const FloatingWorkspaceTabBar({
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseRight,
    this.onCloseAll,
    super.key,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelect;
  final ValueChanged<FloatingTab> onClose;
  final ValueChanged<FloatingTab> onCloseOthers;
  final ValueChanged<FloatingTab> onCloseRight;

  /// Closes every tab in the floating workspace strip.
  final VoidCallback? onCloseAll;

  @override
  Widget build(BuildContext context) {
    final toolsScope = WorkspaceToolsScope.maybeOf(context);
    final workContext = toolsScope?.tools?.context;
    final folderPaths = <String>[
      for (final folder in toolsScope?.effectiveFolders ?? const [])
        folder.path,
    ];
    final pathContext = workContext?.fs.pathContext;
    final desktopShellActions = _desktopShellActionsFor(workContext);
    final remoteFileManagerActions = _remoteFileManagerActionsFor(workContext);

    return TpTabStrip(
      metrics: TpTabStripMetrics.compact,
      fillWidth: false,
      itemCount: tabs.length,
      itemKey: (i) => ValueKey(tabs[i].id),
      onReorder: tabs.length > 1
          ? (oldIndex, newIndex) => context
                .read<FloatingWorkspaceCubit>()
                .reorderTabs(oldIndex, newIndex)
          : null,
      itemBuilder: (context, index) {
        final tab = tabs[index];
        final (kind, filePath) = floatingTabMenuIdentity(tab);
        final workspaceRoot = filePath == null
            ? null
            : resolveContainingWorkspaceRoot(
                filePath,
                folderPaths,
                pathContext: pathContext,
              );
        return WorkbenchStripTabChip(
          kind: kind,
          tabId: tab.id,
          filePath: filePath,
          workspaceRoot: workspaceRoot,
          desktopShellActions: desktopShellActions,
          remoteFileManagerActions: remoteFileManagerActions,
          workContext: workContext,
          title: tab.title,
          active: tab.id == activeTabId,
          icon: _iconFor(tab.surfaceId),
          onTap: () => onSelect(tab.id),
          onClose: () => onClose(tab),
          onCloseOthers: () => onCloseOthers(tab),
          onCloseRight: () => onCloseRight(tab),
          onCloseAll: onCloseAll,
        );
      },
    );
  }

  static IconData _iconFor(String surfaceId) {
    return switch (surfaceId) {
      'terminal' => Icons.terminal_rounded,
      'filePreview' => Icons.description_outlined,
      'diffPreview' => Icons.difference_outlined,
      _ => Icons.widgets_outlined,
    };
  }
}

/// "+" open menu — sibling of [FloatingWorkspaceTabBar], not inside the scroll.
class FloatingWorkspaceAddButton extends StatefulWidget {
  const FloatingWorkspaceAddButton({required this.onOpenFile, super.key});

  final VoidCallback onOpenFile;

  @override
  State<FloatingWorkspaceAddButton> createState() =>
      _FloatingWorkspaceAddButtonState();
}

class _FloatingWorkspaceAddButtonState
    extends State<FloatingWorkspaceAddButton> {
  final _anchorKey = GlobalKey();

  Future<void> _showMenu() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final menuOrigin = anchor + const Offset(0, 4);
    final l10n = context.l10n;
    final selected = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: menuOrigin,
      specs: [
        TpActionMenuSpec.item(
          value: 'terminal',
          label: l10n.workspaceTerminalNewSession,
          icon: Icons.terminal_rounded,
        ),
        TpActionMenuSpec.item(
          value: 'file',
          label: l10n.floatingWorkspaceOpenFile,
          icon: Icons.description_outlined,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'terminal':
        await showFloatingNewTerminalMenu(
          context: context,
          globalPosition: menuOrigin,
        );
      case 'file':
        widget.onOpenFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: TpIconButton(
        key: const Key('floating_workspace_add_button'),
        icon: Icons.add_rounded,
        tooltip: context.l10n.floatingWorkspaceAddTooltip,
        compact: true,
        onTap: () => unawaited(_showMenu()),
      ),
    );
  }
}
