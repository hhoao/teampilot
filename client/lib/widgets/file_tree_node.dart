import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/io/filesystem.dart';
import '../theme/app_text_styles.dart';
import 'file_icon_widget.dart';
import 'file_tree/file_tree_context_menu.dart';
import 'hover_widget.dart';

/// Single row in the flattened file tree (no nested children).
class FileTreeNode extends StatefulWidget {
  const FileTreeNode({
    required this.path,
    required this.entry,
    required this.depth,
    required this.cubit,
    required this.textColor,
    this.desktopShellActions = false,
    this.hoverEnabled = true,
    this.isRoot = false,
    this.rootMissing = false,
    super.key,
  });

  final String path;
  final FsDirEntry entry;
  final int depth;
  final FileTreeCubit cubit;
  final Color textColor;
  final bool desktopShellActions;
  final bool hoverEnabled;

  /// True for a workspace-folder header row in a multi-root tree (rendered with
  /// a stronger label, like VSCode's folder headers).
  final bool isRoot;

  /// True when this root row points at a directory that no longer exists.
  final bool rootMissing;

  @override
  State<FileTreeNode> createState() => _FileTreeNodeState();
}

class _FileTreeNodeState extends State<FileTreeNode> {
  var _hovered = false;

  @override
  void didUpdateWidget(covariant FileTreeNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hoverEnabled && _hovered) {
      _hovered = false;
    }
  }

  void _setHovered(bool value) {
    if (!widget.hoverEnabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

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
    final isExpanded = isDir &&
        context.select<FileTreeCubit, bool>(
          (c) => c.state.expandedPaths.contains(widget.path),
        );
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

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
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
          onSecondaryTapDown: (details) => unawaited(
            FileTreeContextMenu.show(
              context: context,
              tapDetails: details,
              cubit: widget.cubit,
              targetPath: widget.path,
              targetName: widget.entry.name,
              isDirectory: isDir,
              desktopShellActions: widget.desktopShellActions,
            ),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            clipBehavior: Clip.none,
            decoration: rowColor != null
                ? BoxDecoration(
                    color: rowColor,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            padding: EdgeInsets.fromLTRB(
              widget.depth * kFileTreeIndentWidth +
                  kFileTreeNodePaddingLeft +
                  kFileTreeRowHorizontalPadding,
              kFileTreeRowVerticalPadding,
              kFileTreeNodePaddingRight + kFileTreeRowHorizontalPadding,
              kFileTreeRowVerticalPadding,
            ),
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: kFileTreeNodeHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: kFileTreeChevronSlotWidth,
                      child: Center(
                        child: isDir
                            ? AnimatedRotation(
                                turns: isExpanded ? 0.25 : 0.0,
                                duration: const Duration(milliseconds: 150),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: context.appIconSizes.md,
                                  color: isActive
                                      ? iconMuted
                                      : widget.textColor.withValues(alpha: 0.55),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: kFileTreeChevronIconGap),
                    SizedBox(
                      width: context.appIconSizes.md,
                      height: context.appIconSizes.md,
                      child: Center(
                        child: isDir
                            ? Icon(
                                widget.rootMissing
                                    ? Icons.folder_off_outlined
                                    : isExpanded
                                    ? Icons.folder_open
                                    : Icons.folder_outlined,
                                size: context.appIconSizes.md,
                              )
                            : FileIconWidget(
                                fileName: widget.entry.name,
                                size: context.appIconSizes.md,
                              ),
                      ),
                    ),
                    const SizedBox(width: kFileTreeIconLabelGap),
                    Text(
                      widget.entry.name,
                      maxLines: 1,
                      style: AppTextStyles.of(context).body.copyWith(
                        fontWeight: widget.isRoot
                            ? FontWeight.w700
                            : isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: widget.isRoot ? 0.4 : null,
                        color: widget.rootMissing
                            ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                            : labelColor,
                      ),
                    ),
                  ],
                ),
              ),
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
}
