import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/io/filesystem.dart';
import 'menu/sidebar_action_menu.dart';
import '../utils/debounce/debounce.dart';

const _indentWidth = 16.0;

/// Single row in the flattened file tree (no nested children).
class FileTreeNode extends StatelessWidget {
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

  bool _isActiveEditorFile(BuildContext context) {
    if (entry.isDirectory) return false;
    final active = context.select<EditorCubit, String?>(
      (c) => c.state.activePath,
    );
    if (active == null) return false;
    return fileTreePathsEqual(cubit.fs.pathContext, path, active);
  }

  @override
  Widget build(BuildContext context) {
    final isDir = entry.isDirectory;
    final isExpanded = cubit.state.expandedPaths.contains(path);
    final isActive = _isActiveEditorFile(context);
    final cs = Theme.of(context).colorScheme;
    final labelColor = isActive
        ? cs.onSecondaryContainer
        : textColor.withValues(alpha: 0.8);
    final iconMuted = isActive
        ? cs.onSecondaryContainer.withValues(alpha: 0.7)
        : textColor.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: () {
        if (isDir) {
          cubit.toggleExpand(path);
        } else {
          _openFile(context, path);
        }
      },
      onSecondaryTapDown: (details) => _showContextMenu(
        context,
        details.globalPosition,
        path,
        entry.name,
        isDirectory: isDir,
      ),
      child: Container(
        height: 28,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: isActive
            ? BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        padding: EdgeInsets.only(left: depth * _indentWidth + 4, right: 8),
        child: Row(
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
                    size: 16,
                    color: isActive
                        ? iconMuted
                        : textColor.withValues(alpha: 0.55),
                  ),
                ),
              )
            else
              const SizedBox(width: 18),
            Icon(
              isDir
                  ? (isExpanded ? Icons.folder_open : Icons.folder_outlined)
                  : _fileIcon(entry.name),
              size: 18,
              color: isDir ? const Color(0xFFE5B143) : iconMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.of(context).bodySmall.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'yaml':
      case 'yml':
      case 'json':
        return Icons.settings;
      case 'md':
        return Icons.description_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image_outlined;
      case 'zip':
      case 'tar':
      case 'gz':
        return Icons.archive_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  void _openFile(BuildContext context, String filePath) {
    final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (kEditorBinaryExtensions.contains(ext)) {
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
    Offset position,
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
    final value = await showSidebarActionMenuFromSpecs<String>(
      context: context,
      globalPosition: position,
      useRootNavigator: true,
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
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fileTreeDeleteItemTitle),
        content: Text(l10n.fileTreeDeleteItemConfirm(targetName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: throttledOnPressed('file_tree_delete', () {
              Navigator.pop(ctx);
              cubit.deletePath(targetPath);
            }),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
