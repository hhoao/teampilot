import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cubits/file_tree_cubit.dart';

const _indentWidth = 16.0;

class FileTreeNode extends StatelessWidget {
  const FileTreeNode({
    required this.path,
    required this.entity,
    required this.depth,
    required this.cubit,
    this.isLast = true,
    super.key,
  });

  final String path;
  final FileSystemEntity entity;
  final int depth;
  final FileTreeCubit cubit;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isDir = entity is Directory;
    final name = entity.uri.pathSegments.last;
    final isExpanded = cubit.state.expandedPaths.contains(entity.path);
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            if (isDir) {
              cubit.toggleExpand(entity.path);
            } else {
              _openFile(entity.path);
            }
          },
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition, entity.path),
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
                      child: Icon(Icons.chevron_right, size: 16,
                          color: colors.onSurface.withValues(alpha: 0.55)),
                    ),
                  )
                else
                  const SizedBox(width: 18),
                Icon(
                  isDir
                      ? (isExpanded
                          ? Icons.folder_open
                          : Icons.folder_outlined)
                      : _fileIcon(name),
                  size: 18,
                  color: isDir ? const Color(0xFFE5B143) : colors.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isDir && isExpanded)
          _buildChildren(context),
      ],
    );
  }

  Widget _buildChildren(BuildContext context) {
    final entries = cubit.entriesFor(entity.path);
    if (entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: (depth + 1) * _indentWidth + 22),
        child: Text(
          '(empty)',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
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
            path: entries[i].path,
            entity: entries[i],
            depth: depth + 1,
            cubit: cubit,
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

  void _openFile(String filePath) {
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

  void _showContextMenu(BuildContext context, Offset position, String targetPath) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy path')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (value == 'copy') {
      Clipboard.setData(ClipboardData(text: targetPath));
    } else if (value == 'delete' && context.mounted) {
      _confirmDelete(context, targetPath);
    }
  }

  void _confirmDelete(BuildContext context, String targetPath) {
    final name = targetPath.split(Platform.pathSeparator).last;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(targetPath);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _delete(String targetPath) {
    try {
      final entity = FileSystemEntity.typeSync(targetPath);
      if (entity == FileSystemEntityType.directory) {
        Directory(targetPath).deleteSync(recursive: true);
      } else {
        File(targetPath).deleteSync();
      }
      cubit.refresh();
    } catch (_) {}
  }
}
