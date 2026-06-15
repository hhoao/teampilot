import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../theme/app_text_styles.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/io/filesystem.dart';
import 'menu/sidebar_action_menu.dart';
import '../utils/debounce/debounce.dart';
import 'app_dialog.dart';
import 'file_icon_widget.dart';
import 'hover_widget.dart';

/// Single row in the flattened file tree (no nested children).
class FileTreeNode extends StatefulWidget {
  const FileTreeNode({
    required this.path,
    required this.entry,
    required this.depth,
    required this.cubit,
    required this.textColor,
    super.key,
  });

  final String path;
  final FsDirEntry entry;
  final int depth;
  final FileTreeCubit cubit;
  final Color textColor;

  @override
  State<FileTreeNode> createState() => _FileTreeNodeState();
}

class _FileTreeNodeState extends State<FileTreeNode> {
  var _hovered = false;

  bool _isActiveEditorFile(BuildContext context) {
    if (widget.entry.isDirectory) return false;
    final active = context.select<EditorCubit, String?>(
      (c) => c.state.activePath,
    );
    if (active == null) return false;
    return fileTreePathsEqual(widget.cubit.fs.pathContext, widget.path, active);
  }

  @override
  Widget build(BuildContext context) {
    final isDir = widget.entry.isDirectory;
    final isExpanded = widget.cubit.state.expandedPaths.contains(widget.path);
    final isActive = _isActiveEditorFile(context);
    final canOpenInEditor = !isDir && isEditorOpenableFilePath(widget.path);
    final cs = Theme.of(context).colorScheme;
    final labelColor = isActive
        ? cs.onSecondaryContainer
        : isDir
        ? widget.textColor.withValues(alpha: 0.8)
        : canOpenInEditor
        ? widget.textColor.withValues(alpha: 0.92)
        : cs.onSurfaceVariant.withValues(alpha: 0.52);
    final iconMuted = isActive
        ? cs.onSecondaryContainer.withValues(alpha: 0.7)
        : isDir
        ? widget.textColor.withValues(alpha: 0.6)
        : canOpenInEditor
        ? widget.textColor.withValues(alpha: 0.65)
        : cs.onSurfaceVariant.withValues(alpha: 0.45);
    final rowColor = isActive
        ? cs.secondaryContainer
        : _hovered
        ? HoverWidget.defaultHoverColor(context)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isDir) {
            widget.cubit.toggleExpand(widget.path);
          } else {
            _openFile(context, widget.path);
          }
        },
        onSecondaryTapDown: (details) => _showContextMenu(
          context,
          details,
          widget.path,
          widget.entry.name,
          isDirectory: isDir,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: double.infinity,
          clipBehavior: Clip.none,
          decoration: rowColor != null
              ? BoxDecoration(
                  color: rowColor,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          padding: EdgeInsets.only(
            left: widget.depth * kFileTreeIndentWidth + kFileTreeNodePaddingLeft,
            right: kFileTreeNodePaddingRight,
          ),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
              if (isDir)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: context.appIconSizes.md,
                      color: isActive
                          ? iconMuted
                          : widget.textColor.withValues(alpha: 0.55),
                    ),
                  ),
                )
              else
                const SizedBox(width: 18),
              if (isDir)
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder_outlined,
                  size: context.appIconSizes.md,
                )
              else
                FileIconWidget(
                  fileName: widget.entry.name,
                  size: context.appIconSizes.md,
                ),
              const SizedBox(width: 6),
              Text(
                widget.entry.name,
                maxLines: 1,
                style: AppTextStyles.of(context).body.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFile(BuildContext context, String filePath) {
    if (!isEditorOpenableFilePath(filePath)) {
      _openFileExternally(filePath);
      return;
    }
    unawaited(context.read<EditorCubit>().openFile(filePath));
  }

  void _openFileExternally(String filePath) {
    try {
      if (Platform.isLinux) {
        Process.run('xdg-open', [filePath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [filePath]);
      } else if (Platform.isWindows) {
        Process.run('start', [filePath], runInShell: true);
      }
    } catch (_) {}
  }

  void _showContextMenu(
    BuildContext context,
    TapDownDetails tapDetails,
    String targetPath,
    String targetName, {
    required bool isDirectory,
  }) async {
    final l10n = context.l10n;
    final specs = <SidebarActionMenuSpec>[
      if (!isDirectory)
        SidebarActionMenuSpec.item(
          value: 'external',
          icon: Icons.open_in_new,
          label: l10n.fileTreeOpenWithSystemApp,
        ),
      SidebarActionMenuSpec.item(
        value: 'copy',
        icon: Icons.copy,
        label: l10n.fileTreeCopyPath,
      ),
      const SidebarActionMenuSpec.divider(),
      SidebarActionMenuSpec.item(
        value: 'delete',
        icon: Icons.delete_outline,
        label: l10n.fileTreeDeleteItemTitle,
        destructive: true,
      ),
    ];
    final value = await showSidebarActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (value == 'external' && !isDirectory) {
      _openFileExternally(targetPath);
    } else if (value == 'copy') {
      Clipboard.setData(ClipboardData(text: targetPath));
    } else if (value == 'delete' && context.mounted) {
      _confirmDelete(context, targetPath, targetName);
    }
  }

  void _confirmDelete(
    BuildContext context,
    String targetPath,
    String targetName,
  ) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.fileTreeDeleteItemTitle),
            const SizedBox(height: 16),
            Text(l10n.fileTreeDeleteItemConfirm(targetName)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: throttledOnPressed('file_tree_delete', () {
                    Navigator.pop(ctx);
                    widget.cubit.deletePath(targetPath);
                  }),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
