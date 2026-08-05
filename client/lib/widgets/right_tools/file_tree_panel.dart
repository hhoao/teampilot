import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/file_tree_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_projection.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/file_tree/file_tree_visible_rows.dart';
import '../../services/file_tree_import/file_tree_drop_hit_test.dart';
import '../../services/file_tree_import/file_tree_drop_ingestor.dart';
import '../../services/file_tree_import/import_models.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace_dnd/workspace_file_ref.dart';
import '../../utils/ui/app_keys.dart';
import '../file_tree/file_tree_drop_region.dart';
import '../file_tree/file_tree_import_dialogs.dart';
import '../file_tree_node.dart';
import 'file_tree_header_overflow_menu.dart';
import 'right_tools_lifecycle.dart';

/// Workspace file tree panel.
///
/// Pure view over an injected [FileTreeCubit] from [WorkspaceFileTreeStore].
///
/// A single workspace folder shows its children directly; multiple folders each
/// get a collapsible header (VSCode multi-root layout).
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    required this.cubit,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  final FileTreeCubit cubit;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  bool _filterVisible = false;
  bool _listReady = false;

  FileTreeCubit get _cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    // Filter lives in the cubit; sync the text field when the panel remounts.
    _filterController.text = _cubit.state.filterText;
    // Stagger list mount one frame after the header so first paint stays light.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RightToolsLifecycle.of(context).ensureFileTreeReady();
      setState(() => _listReady = true);
    });
  }

  void _toggleFilterVisible() {
    setState(() {
      _filterVisible = !_filterVisible;
      if (!_filterVisible) {
        _filterController.clear();
        _cubit.setFilter('');
      }
    });
  }

  Future<void> _revealActiveEditorFile() async {
    if (!mounted) return;
    final active = context.read<WorkbenchCubit>().activeTabId(widget.workspaceId);
    if (active == null || active.kind != WorkbenchTabKind.file) return;

    _filterController.clear();
    final ok = await _cubit.revealPath(active.id);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: context.l10n.fileTreeRevealFailed,
        variant: TpToastVariant.error,
      );
      return;
    }
    _scheduleRevealScroll();
  }

  void _scheduleRevealScroll([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final target = _cubit.state.revealPath;
      if (target == null) return;

      if (!_listScrollController.hasClients) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        }
        return;
      }

      final rows = _cubit.state.visibleRows;
      final index = visibleRowIndexForPath(
        rows,
        target,
        _cubit.fsFor(target).pathContext,
      );
      if (index == null) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        } else if (mounted) {
          _cubit.clearRevealPath();
        }
        return;
      }

      final position = _listScrollController.position;
      final viewport = position.viewportDimension;
      final rowTop = index * kFileTreeRowExtent;
      final targetOffset = (rowTop - viewport * 0.35).clamp(
        0.0,
        position.maxScrollExtent,
      );
      await _listScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (mounted) {
        _cubit.clearRevealPath();
      }
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _listScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return BlocProvider.value(
      value: _cubit,
      child: Container(
        key: AppKeys.fileTreePanel,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlocSelector<FileTreeCubit, FileTreeState, (bool, bool, String)>(
              selector: (state) => (
                state.expandedPaths.isNotEmpty,
                state.showHiddenFiles,
                state.rootPath,
              ),
              builder: (context, header) {
                final (hasExpandedFolders, showHiddenFiles, rootPath) = header;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    const actionSlotWidth = 28.0;
                    final actionCount = (hasExpandedFolders ? 5 : 4) + 1;
                    final showInlineActions =
                        constraints.maxWidth >= actionSlotWidth * actionCount;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.fileTree,
                            style: TpTextStyles.of(
                              context,
                            ).xsBoldWideColored(cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (showInlineActions)
                          ..._buildFileTreeHeaderActions(
                            l10n: l10n,
                            showHiddenFiles: showHiddenFiles,
                            rootPath: rootPath,
                            filterVisible: _filterVisible,
                          )
                        else
                          FileTreeHeaderOverflowMenu(
                            l10n: l10n,
                            showHiddenFiles: showHiddenFiles,
                            filterVisible: _filterVisible,
                            hasExpandedFolders: hasExpandedFolders,
                            canCopy: rootPath.isNotEmpty,
                            onRefresh: _cubit.refresh,
                            onReveal: () =>
                                unawaited(_revealActiveEditorFile()),
                            onCollapseAll: _cubit.collapseAllFolders,
                            onToggleFilter: _toggleFilterVisible,
                            onToggleHidden: _cubit.toggleShowHidden,
                            onCopy: () {
                              if (rootPath.isNotEmpty) {
                                Clipboard.setData(
                                  ClipboardData(text: rootPath),
                                );
                              }
                            },
                          ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_filterVisible) ...[
                    _FileTreeFilterField(
                      controller: _filterController,
                      hintText: l10n.filterFiles,
                      onFilterChanged: _cubit.setFilter,
                      onClear: () {
                        _filterController.clear();
                        _cubit.setFilter('');
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_listReady) ...[
                    // Single-root: show the folder path. Multi-root: each root
                    // gets its own header row, so the single path line is hidden.
                    BlocSelector<
                      FileTreeCubit,
                      FileTreeState,
                      (bool, bool, String)
                    >(
                      selector: (state) => (
                        state.isMultiRoot,
                        state.anyRootExists,
                        state.rootPath,
                      ),
                      builder: (context, root) {
                        final (isMultiRoot, anyRootExists, rootPath) = root;
                        if (isMultiRoot) return const SizedBox.shrink();
                        if (anyRootExists) {
                          return Text(
                            rootPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TpTextStyles.of(
                              context,
                            ).smColored(cs.onSurfaceVariant),
                          );
                        }
                        return Text(
                          'Directory unavailable',
                          style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FileTreeDropRegion(
                        cubit: _cubit,
                        listScrollController: _listScrollController,
                        workspaceId: widget.workspaceId,
                        child:
                            BlocSelector<
                              FileTreeCubit,
                              FileTreeState,
                              List<FileTreeVisibleRow>
                            >(
                              selector: (state) => state.visibleRows,
                              builder: (context, rows) {
                                if (!context
                                    .read<FileTreeCubit>()
                                    .state
                                    .anyRootExists) {
                                  return const SizedBox.shrink();
                                }
                                return _FloatingPreviewHighlight(
                                  workspaceId: widget.workspaceId,
                                  builder: (context, path) => _FileTreeList(
                                    rows: rows,
                                    cubit: _cubit,
                                    textColor: cs.onSurface,
                                    listScrollController:
                                        _listScrollController,
                                    horizontalScrollController:
                                        _horizontalScrollController,
                                    desktopShellActions:
                                        _desktopShellActionsFor(
                                          _workContext,
                                        ),
                                    remoteFileManagerActions:
                                        _remoteFileManagerActionsFor(
                                          _workContext,
                                        ),
                                    workContext: _workContext,
                                    workspaceId: widget.workspaceId,
                                    activeFloatingFilePath: path,
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                  ] else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFileTreeHeaderActions({
    required AppLocalizations l10n,
    required bool showHiddenFiles,
    required String rootPath,
    required bool filterVisible,
  }) {
    final actions = <Widget>[
      TpIconButton(
        icon: filterVisible ? Icons.search_off : Icons.search,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: filterVisible
            ? l10n.fileTreeHideFilter
            : l10n.fileTreeShowFilter,
        onTap: _toggleFilterVisible,
      ),
      TpIconButton(
        icon: Icons.refresh,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.fileTreeRefresh,
        onTap: _cubit.refresh,
      ),
      TpIconButton(
        icon: Icons.my_location_outlined,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
    ];
    actions.add(
      TpIconButton(
        icon: Icons.unfold_less,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.treeCollapseAllFolders,
        onTap: _cubit.collapseAllFolders,
      ),
    );
    actions.addAll([
      TpIconButton(
        icon: showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
        onTap: _cubit.toggleShowHidden,
      ),
      TpIconButton(
        icon: Icons.copy,
        iconSize: context.tpIconSizes.md,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.copy,
        onTap: () {
          if (rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: rootPath));
          }
        },
      ),
    ]);
    return actions;
  }

  RuntimeContext get _workContext => widget.workContext;

  bool _desktopShellActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.native ||
        ctx.mode == StorageBackendMode.wsl;
  }

  bool _remoteFileManagerActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.ssh;
  }
}

/// Filter row isolated from the file tree list so keystrokes do not rebuild rows.
class _FileTreeFilterField extends StatelessWidget {
  const _FileTreeFilterField({
    required this.controller,
    required this.hintText,
    required this.onFilterChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            suffixIcon: value.text.isNotEmpty
                ? TpIconButton(
                    icon: Icons.clear,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    onTap: onClear,
                  )
                : null,
          ),
          onChanged: onFilterChanged,
        );
      },
    );
  }
}

/// Surface id of the floating file-preview tab (mirrors
/// `FilePreviewFloatingSurface.id`; the file tree decides what counts as a
/// highlight — the cubit stays surface-agnostic).
const String _kFloatingFilePreviewSurfaceId = 'filePreview';

/// Projects the active floating file-preview path for [workspaceId] and
/// rebuilds [builder] only when that path actually changes.
///
/// Unrelated tab opens / switches cost one cheap projection recompute (no
/// notify on unchanged value) instead of rebuilding the whole file tree.
class _FloatingPreviewHighlight extends StatefulWidget {
  const _FloatingPreviewHighlight({
    required this.workspaceId,
    required this.builder,
  });

  final String workspaceId;
  final Widget Function(BuildContext context, String? path) builder;

  @override
  State<_FloatingPreviewHighlight> createState() =>
      _FloatingPreviewHighlightState();
}

class _FloatingPreviewHighlightState extends State<_FloatingPreviewHighlight> {
  FloatingWorkspaceProjection<String?>? _projection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _projection ??= FloatingWorkspaceProjection<String?>(
      context.read<FloatingWorkspaceCubit>(),
      _projectPath,
      initial: null,
    );
  }

  String? _projectPath(FloatingWorkspaceCubit cubit) {
    final active = cubit.activeTabFor(widget.workspaceId);
    if (active == null ||
        active.surfaceId != _kFloatingFilePreviewSurfaceId) {
      return null;
    }
    return active.payload is String ? active.payload as String : null;
  }

  @override
  void dispose() {
    _projection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _projection!,
      builder: (context, path, _) => widget.builder(context, path),
    );
  }
}

class _FileTreeList extends StatefulWidget {
  const _FileTreeList({
    required this.rows,
    required this.cubit,
    required this.textColor,
    required this.listScrollController,
    required this.horizontalScrollController,
    required this.desktopShellActions,
    required this.remoteFileManagerActions,
    required this.workContext,
    required this.workspaceId,
    required this.activeFloatingFilePath,
  });

  final List<FileTreeVisibleRow> rows;
  final FileTreeCubit cubit;
  final Color textColor;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;
  final RuntimeContext workContext;
  final String workspaceId;
  final String? activeFloatingFilePath;

  @override
  State<_FileTreeList> createState() => _FileTreeListState();
}

class _FileTreeListState extends State<_FileTreeList> {
  var _hoverEnabled = true;
  var _activeScrolls = 0;

  bool _desktopShellActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.native ||
        ctx.mode == StorageBackendMode.wsl;
  }

  bool _remoteFileManagerActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.ssh;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _activeScrolls++;
      if (_hoverEnabled) setState(() => _hoverEnabled = false);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _activeScrolls = (_activeScrolls - 1).clamp(0, 1 << 30);
      if (_activeScrolls == 0 && !_hoverEnabled) {
        setState(() => _hoverEnabled = true);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) {
      return Text(
        '(empty)',
        style: TpTextStyles.of(
          context,
        ).smColored(widget.textColor.withValues(alpha: 0.35)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = TpTextStyles.of(context).md;
        final emptyLabelStyle = TpTextStyles.of(context).xs;
        final contentWidth = math.max(
          constraints.maxWidth,
          fileTreeMinContentWidth(
            rows: rows,
            labelStyle: labelStyle,
            emptyLabelStyle: emptyLabelStyle,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        );

        return Scrollbar(
          controller: widget.horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: widget.horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: widget.listScrollController,
                thumbVisibility: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView.builder(
                    scrollCacheExtent: ScrollCacheExtent.pixels(400),
                    controller: widget.listScrollController,
                    itemCount: rows.length,
                    itemExtent: kFileTreeRowExtent,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row.isEmptyPlaceholder) {
                        final placeholder = SizedBox(
                          width: contentWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: kFileTreeRowVerticalPadding,
                              horizontal: kFileTreeRowHorizontalPadding,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left:
                                      row.depth * kFileTreeIndentWidth +
                                      kFileTreeNodePaddingLeft +
                                      kFileTreeChevronSlotWidth,
                                ),
                                child: Text(
                                  '(empty)',
                                  style: TpTextStyles.of(context).xs.copyWith(
                                    color: widget.textColor.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        final dropHost = FileTreeDropScope.maybeOf(context);
                        if (dropHost == null) return placeholder;
                        return DragTarget<WorkspaceDragPayload>(
                          onWillAcceptWithDetails: (details) {
                            return details.data.kind ==
                                    DragPayloadKind.workspaceFile &&
                                details.data.refs.isNotEmpty;
                          },
                          onAcceptWithDetails: (details) {
                            final hit = resolveFileTreeDropDest(
                              kind: FileTreeDropRowKind.empty,
                              rowPath: row.path,
                              pathContext: widget.cubit
                                  .fsFor(row.path)
                                  .pathContext,
                              sourcePaths: [
                                for (final ref in details.data.refs)
                                  ref.nativePath,
                              ],
                            );
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
                            final inTreeHover =
                                candidates.isNotEmpty &&
                                candidates.first != null;
                            final osHover =
                                dropHost.osHoverRowPath != null &&
                                fileTreePathsEqual(
                                  widget.cubit.fsFor(row.path).pathContext,
                                  dropHost.osHoverRowPath!,
                                  row.path,
                                );
                            ImportMode? affordance;
                            if (inTreeHover) {
                              final payload = candidates.first!;
                              final sourcePath =
                                  payload.refs.first.nativePath;
                              final sameFs = fileTreePathsShareFilesystem(
                                sourceFs: widget.cubit.fsFor(sourcePath),
                                destFs: widget.cubit.fsFor(row.path),
                                sourceWorkContext: widget.cubit
                                    .workContextFor(sourcePath),
                                destWorkContext: widget.cubit.workContextFor(
                                  row.path,
                                ),
                              );
                              affordance = resolveFileTreeImportMode(
                                fromExternalOs: false,
                                sameFs: sameFs,
                                copyModifier: fileTreeCopyModifierPressed(),
                              );
                            } else if (osHover) {
                              affordance = dropHost.osHoverAffordance;
                            }
                            return FileTreeDropHighlight(
                              active: inTreeHover || osHover,
                              affordance: affordance,
                              child: placeholder,
                            );
                          },
                        );
                      }
                      return SizedBox(
                        width: contentWidth,
                        child: FileTreeNode(
                          key: ValueKey(
                            row.isRoot ? 'root:${row.path}' : row.path,
                          ),
                          path: row.path,
                          entry: row.entry,
                          depth: row.depth,
                          cubit: widget.cubit,
                          textColor: widget.textColor,
                          workspaceId: widget.workspaceId,
                          desktopShellActions: _desktopShellActionsFor(
                            widget.cubit.workContextFor(row.path) ??
                                widget.workContext,
                          ),
                          remoteFileManagerActions:
                              _remoteFileManagerActionsFor(
                                widget.cubit.workContextFor(row.path) ??
                                    widget.workContext,
                              ),
                          workContext:
                              widget.cubit.workContextFor(row.path) ??
                              widget.workContext,
                          hoverEnabled: _hoverEnabled,
                          isRoot: row.isRoot,
                          rootMissing: row.rootMissing,
                          activeFloatingFilePath:
                              widget.activeFloatingFilePath,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
