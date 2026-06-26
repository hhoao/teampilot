import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/file_tree_cubit.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/file_tree/file_tree_visible_rows.dart';
import '../../services/io/filesystem.dart';
import '../../services/storage/runtime_context.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/app_keys.dart';
import '../app_icon_button.dart';
import '../file_tree_node.dart';
import 'file_tree_header_overflow_menu.dart';

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
    super.key,
  });

  final FileTreeCubit cubit;
  final RuntimeContext workContext;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  EditorCubit? _editorCubit;

  FileTreeCubit get _cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    // Filter lives in the cubit; sync the text field when the panel remounts.
    _filterController.text = _cubit.state.filterText;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _editorCubit = context.read<EditorCubit>();
  }

  Future<void> _revealActiveEditorFile() async {
    if (!mounted) return;
    final active = _editorCubit?.state.activePath;
    if (active == null) return;

    _filterController.clear();
    final ok = await _cubit.revealPath(active);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: context.l10n.fileTreeRevealFailed,
        variant: AppToastVariant.error,
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
                    final actionCount = hasExpandedFolders ? 5 : 4;
                    final showInlineActions =
                        constraints.maxWidth >= actionSlotWidth * actionCount;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.fileTree,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (showInlineActions)
                          ..._buildFileTreeHeaderActions(
                            l10n: l10n,
                            showHiddenFiles: showHiddenFiles,
                            rootPath: rootPath,
                          )
                        else
                          FileTreeHeaderOverflowMenu(
                            l10n: l10n,
                            showHiddenFiles: showHiddenFiles,
                            hasExpandedFolders: hasExpandedFolders,
                            canCopy: rootPath.isNotEmpty,
                            onRefresh: _cubit.refresh,
                            onReveal: () =>
                                unawaited(_revealActiveEditorFile()),
                            onCollapseAll: _cubit.collapseAllFolders,
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
                  TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      hintText: l10n.filterFiles,
                      prefixIcon: Icon(
                        Icons.search,
                        size: context.appIconSizes.md,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      suffixIcon: _filterController.text.isNotEmpty
                          ? AppIconButton(
                              icon: Icons.clear,
                              compact: true,
                              size: AppIconButton.kCompactSize,
                              onTap: () {
                                _filterController.clear();
                                _cubit.setFilter('');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) {
                      _cubit.setFilter(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  // Single-root: show the folder path. Multi-root: each root
                  // gets its own header row, so the single path line is hidden.
                  BlocSelector<FileTreeCubit, FileTreeState, (bool, bool, String)>(
                    selector: (state) =>
                        (state.isMultiRoot, state.anyRootExists, state.rootPath),
                    builder: (context, root) {
                      final (isMultiRoot, anyRootExists, rootPath) = root;
                      if (isMultiRoot) return const SizedBox.shrink();
                      if (anyRootExists) {
                        return Text(
                          rootPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(
                            context,
                          ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                        );
                      }
                      return Text(
                        'Directory unavailable',
                        style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: BlocSelector<FileTreeCubit, FileTreeState,
                        List<FileTreeVisibleRow>>(
                      selector: (state) => state.visibleRows,
                      builder: (context, rows) {
                        if (!context.read<FileTreeCubit>().state.anyRootExists) {
                          return const SizedBox.shrink();
                        }
                        return _FileTreeList(
                          rows: rows,
                          cubit: _cubit,
                          textColor: cs.onSurface,
                          listScrollController: _listScrollController,
                          horizontalScrollController:
                              _horizontalScrollController,
                          desktopShellActions:
                              _desktopShellActionsFor(_workContext),
                          remoteFileManagerActions:
                              _remoteFileManagerActionsFor(_workContext),
                          workContext: _workContext,
                        );
                      },
                    ),
                  ),
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
  }) {
    final actions = <Widget>[
      AppIconButton(
        icon: Icons.refresh,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRefresh,
        onTap: _cubit.refresh,
      ),
      AppIconButton(
        icon: Icons.my_location_outlined,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
    ];
    actions.add(
      AppIconButton(
        icon: Icons.unfold_less,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.treeCollapseAllFolders,
        onTap: _cubit.collapseAllFolders,
      ),
    );
    actions.addAll([
      AppIconButton(
        icon: showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: showHiddenFiles
            ? 'Hide hidden files'
            : 'Show hidden files',
        onTap: _cubit.toggleShowHidden,
      ),
      AppIconButton(
        icon: Icons.copy,
        iconSize: context.appIconSizes.md,
        size: AppIconButton.kCompactSize,
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
  });

  final List<FileTreeVisibleRow> rows;
  final FileTreeCubit cubit;
  final Color textColor;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;
  final RuntimeContext workContext;

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
        style: AppTextStyles.of(
          context,
        ).bodySmall.copyWith(color: widget.textColor.withValues(alpha: 0.35)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = AppTextStyles.of(
          context,
        ).body.copyWith(fontWeight: FontWeight.w500);
        final emptyLabelStyle = AppTextStyles.of(context).caption;
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
                    controller: widget.listScrollController,
                    cacheExtent: 400,
                    itemCount: rows.length,
                    itemExtent: kFileTreeRowExtent,
                    itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.isEmptyPlaceholder) {
                      return SizedBox(
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
                                style: AppTextStyles.of(context).caption
                                    .copyWith(
                                      color: widget.textColor.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return SizedBox(
                      width: contentWidth,
                      child: FileTreeNode(
                        key: ValueKey(row.isRoot ? 'root:${row.path}' : row.path),
                        path: row.path,
                        entry: row.entry,
                        depth: row.depth,
                        cubit: widget.cubit,
                        textColor: widget.textColor,
                        desktopShellActions: _desktopShellActionsFor(
                          widget.cubit.workContextFor(row.path) ??
                              widget.workContext,
                        ),
                        remoteFileManagerActions: _remoteFileManagerActionsFor(
                          widget.cubit.workContextFor(row.path) ??
                              widget.workContext,
                        ),
                        workContext:
                            widget.cubit.workContextFor(row.path) ??
                            widget.workContext,
                        hoverEnabled: _hoverEnabled,
                        isRoot: row.isRoot,
                        rootMissing: row.rootMissing,
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
