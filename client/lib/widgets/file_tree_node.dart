import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../cubits/file_tree_cubit.dart';
import '../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../cubits/workbench/workbench_tab.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/file_tree_import/file_tree_drop_hit_test.dart';
import '../services/file_tree_import/file_tree_drop_ingestor.dart';
import '../services/file_tree_import/import_models.dart';
import '../services/io/file_path_actions.dart';
import '../services/io/filesystem.dart';
import '../services/storage/runtime_context.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workspace_dnd/path_namespace.dart';
import '../services/workspace_dnd/workspace_file_ref.dart';
import 'file_icon_widget.dart';
import 'file_tree/file_tree_context_menu.dart';
import 'file_tree/file_tree_drop_region.dart';
import 'file_tree/file_tree_import_dialogs.dart';
import 'workspace_dnd/draggable_file_row.dart';

/// Single row in the flattened file tree (no nested children).
class FileTreeNode extends StatefulWidget {
  const FileTreeNode({
    required this.path,
    required this.entry,
    required this.depth,
    required this.cubit,
    required this.textColor,
    required this.workspaceId,
    this.desktopShellActions = false,
    this.remoteFileManagerActions = false,
    required this.workContext,
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
  final String workspaceId;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;
  final RuntimeContext workContext;
  final bool hoverEnabled;

  /// True for a workspace-folder header row in a multi-root tree.
  final bool isRoot;

  /// True when this root row points at a directory that no longer exists.
  final bool rootMissing;

  @override
  State<FileTreeNode> createState() => _FileTreeNodeState();
}

class _FileTreeNodeState extends State<FileTreeNode> {
  DateTime? _lastTapAt;
  String? _lastTapPath;

  static const _doubleTapWindow = Duration(milliseconds: 300);

  bool _isActiveEditorFile(BuildContext context) {
    if (widget.entry.isDirectory) return false;
    final pathCtx = widget.cubit.fs.pathContext;
    final active = context.select<WorkbenchCubit, WorkbenchTabId?>(
      (c) => c.activeTabId(widget.workspaceId),
    );
    if (active != null &&
        active.kind == WorkbenchTabKind.file &&
        fileTreePathsEqual(pathCtx, widget.path, active.id)) {
      return true;
    }
    // Floating file-preview host: active tab lives on FloatingWorkspaceCubit.
    final floatingPath = context.select<FloatingWorkspaceCubit, String?>((c) {
      if (c.state.activeWorkspaceId != widget.workspaceId) return null;
      final bucket = c.state.activeBucket;
      final activeId = bucket.activeTabId;
      if (activeId == null) return null;
      for (final tab in bucket.tabs) {
        if (tab.id != activeId) continue;
        if (tab.surfaceId != 'filePreview') return null;
        final payload = tab.payload;
        return payload is String ? payload : null;
      }
      return null;
    });
    if (floatingPath == null || floatingPath.isEmpty) return false;
    return fileTreePathsEqual(pathCtx, widget.path, floatingPath);
  }

  /// Manual double-tap so single-click preview is not delayed by
  /// [GestureDetector.onDoubleTap] (~[kDoubleTapTimeout]).
  void _handleFileTap(BuildContext context, String filePath) {
    final now = DateTime.now();
    final isDouble =
        _lastTapPath == filePath &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < _doubleTapWindow;
    _lastTapAt = now;
    _lastTapPath = filePath;
    _openFile(context, filePath, preview: !isDouble);
  }

  FileTreeDropHit _hitForPayload(WorkspaceDragPayload payload) {
    return resolveFileTreeDropDest(
      kind: widget.isRoot
          ? FileTreeDropRowKind.rootChrome
          : widget.entry.isDirectory
          ? FileTreeDropRowKind.folder
          : FileTreeDropRowKind.file,
      rowPath: widget.path,
      pathContext: widget.cubit.fsFor(widget.path).pathContext,
      sourcePaths: [for (final ref in payload.refs) ref.nativePath],
    );
  }

  ImportMode _affordanceFor(WorkspaceDragPayload payload) {
    final sourcePath = payload.refs.first.nativePath;
    final destHit = _hitForPayload(payload);
    final destDir = destHit.destDir ?? widget.path;
    final sameFs = fileTreePathsShareFilesystem(
      sourceFs: widget.cubit.fsFor(sourcePath),
      destFs: widget.cubit.fsFor(destDir),
      sourceWorkContext: widget.cubit.workContextFor(sourcePath),
      destWorkContext: widget.cubit.workContextFor(destDir),
    );
    return resolveFileTreeImportMode(
      fromExternalOs: false,
      sameFs: sameFs,
      copyModifier: fileTreeCopyModifierPressed(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDir = widget.entry.isDirectory;
    final isExpanded =
        isDir &&
        context.select<FileTreeCubit, bool>(
          (c) => c.state.expandedPaths.contains(widget.path),
        );
    final isActive = _isActiveEditorFile(context);
    final canOpenInEditor = !isDir && isWorkbenchOpenableFilePath(widget.path);
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
    final dropHost = FileTreeDropScope.maybeOf(context);
    final osHover =
        dropHost != null &&
        dropHost.osHoverRowPath != null &&
        fileTreePathsEqual(
          widget.cubit.fsFor(widget.path).pathContext,
          dropHost.osHoverRowPath!,
          widget.path,
        );

    final payload = WorkspaceDragPayload.singleFile(
      WorkspaceFileRef(
        nativePath: widget.path,
        namespace: PathNamespace.ofCurrentStorage(),
        isDirectory: isDir,
      ),
    );

    final activeFill = isActive ? cs.secondaryContainer : null;
    final rowBody = DraggableFileRow(
      enabled: !widget.isRoot && !widget.rootMissing,
      label: widget.entry.name,
      payload: payload,
      child: TpHover(
        onTap: () {
          if (isDir) {
            widget.cubit.toggleExpand(widget.path);
          } else {
            _handleFileTap(context, widget.path);
          }
        },
        onSecondaryTapDown: (details) {
          final folderPaths = [
            for (final root in widget.cubit.state.roots) root.path,
          ];
          final workspaceRoot = resolveContainingWorkspaceRoot(
            widget.path,
            folderPaths,
            pathContext: widget.cubit.fs.pathContext,
          );
          unawaited(
            FileTreeContextMenu.show(
              context: context,
              tapDetails: details,
              cubit: widget.cubit,
              targetPath: widget.path,
              targetName: widget.entry.name,
              isDirectory: isDir,
              desktopShellActions: widget.desktopShellActions,
              remoteFileManagerActions: widget.remoteFileManagerActions,
              workContext: widget.workContext,
              workspaceId: widget.workspaceId,
              workspaceRoot: workspaceRoot,
            ),
          );
        },
        backgroundColor: activeFill,
        hoverColor: widget.hoverEnabled
            ? activeFill
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
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
                              size: context.tpIconSizes.md,
                              color: isActive
                                  ? iconMuted
                                  : widget.textColor.withValues(
                                      alpha: 0.55,
                                    ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: kFileTreeChevronIconGap),
                SizedBox(
                  width: context.tpIconSizes.md,
                  height: context.tpIconSizes.md,
                  child: Center(
                    child: isDir
                        ? Icon(
                            widget.rootMissing
                                ? Icons.folder_off_outlined
                                : isExpanded
                                ? Icons.folder_open
                                : Icons.folder_outlined,
                            size: context.tpIconSizes.md,
                          )
                        : FileIconWidget(
                            fileName: widget.entry.name,
                            size: context.tpIconSizes.md,
                          ),
                  ),
                ),
                const SizedBox(width: kFileTreeIconLabelGap),
                Text(
                  widget.entry.name,
                  maxLines: 1,
                  style: TpTextStyles.of(context).mdColored(
                    widget.rootMissing
                        ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                        : labelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (dropHost == null || widget.rootMissing) {
      return RepaintBoundary(child: rowBody);
    }

    return RepaintBoundary(
      child: DragTarget<WorkspaceDragPayload>(
        onWillAcceptWithDetails: (details) {
          // Accept by kind so ontoSelf reaches onAccept (toast); do not
          // pre-filter with hit validity here.
          return details.data.kind == DragPayloadKind.workspaceFile &&
              details.data.refs.isNotEmpty;
        },
        onAcceptWithDetails: (details) {
          final hit = _hitForPayload(details.data);
          switch (resolveFileTreeDropAcceptAction(hit)) {
            case FileTreeDropAcceptAction.ingest:
              unawaited(
                dropHost.ingest(
                  destDir: hit.destDir!,
                  payload: details.data,
                  fromExternalOs: false,
                ),
              );
            case FileTreeDropAcceptAction.rejectSelf:
              if (context.mounted) {
                showFileTreeImportRejectSelfToast(context);
              }
            case FileTreeDropAcceptAction.ignore:
              break;
          }
        },
        builder: (context, candidates, rejected) {
          final inTreeHover = candidates.isNotEmpty && candidates.first != null;
          final affordance = inTreeHover
              ? _affordanceFor(candidates.first!)
              : osHover
              ? dropHost.osHoverAffordance
              : null;
          return FileTreeDropHighlight(
            active: inTreeHover || osHover,
            affordance: affordance,
            child: rowBody,
          );
        },
      ),
    );
  }

  void _openFile(
    BuildContext context,
    String filePath, {
    required bool preview,
  }) {
    if (!isWorkbenchOpenableFilePath(filePath)) {
      _openFileExternally(filePath);
      return;
    }
    unawaited(
      context.read<WorkbenchEditorOpener>().openFile(
        widget.workspaceId,
        filePath,
        fs: widget.cubit.fsFor(filePath),
        preview: preview,
      ),
    );
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
