import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/io/filesystem.dart';
import '../utils/debounce/debounce.dart';

const _indentWidth = 16.0;

class FileTreeNode extends StatelessWidget {
  const FileTreeNode({
    required this.path,
    required this.entry,
    required this.depth,
    required this.cubit,
    required this.textColor,
    this.isLast = true,
    super.key,
  });

  final String path;
  final FsDirEntry entry;
  final int depth;
  final FileTreeCubit cubit;
  final Color textColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isDir = entry.isDirectory;
    final isExpanded = cubit.state.expandedPaths.contains(path);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
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
                        color: textColor.withValues(alpha: 0.55),
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
                  color: isDir
                      ? const Color(0xFFE5B143)
                      : textColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isDir && isExpanded) _buildChildren(context),
      ],
    );
  }

  Widget _buildChildren(BuildContext context) {
    final entries = cubit.entriesFor(path);
    if (entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: (depth + 1) * _indentWidth + 22),
        child: Text(
          '(empty)',
          style: TextStyle(
            fontSize: 11,
            color: textColor.withValues(alpha: 0.35),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          FileTreeNode(
            path: cubit.fs.pathContext.join(path, entries[i].name),
            entry: entries[i],
            depth: depth + 1,
            cubit: cubit,
            textColor: textColor,
            isLast: i == entries.length - 1,
          ),
      ],
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
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (!isDirectory)
          const PopupMenuItem(
            value: 'external',
            child: Text('Open with system app'),
          ),
        const PopupMenuItem(value: 'copy', child: Text('Copy path')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (value == 'external' && !isDirectory) {
      _openFileExternally(targetPath);
    } else if (value == 'copy') {
      Clipboard.setData(ClipboardData(text: targetPath));
    } else if (value == 'delete' && context.mounted) {
      _confirmDelete(context, targetPath, targetName);
    }
  }

  void _confirmDelete(BuildContext context, String targetPath, String targetName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "$targetName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: throttledOnPressed('file_tree_delete', () {
              Navigator.pop(ctx);
              cubit.deletePath(targetPath);
            }),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
