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
import '../../services/io/workspace_fs_watcher.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/runtime_storage_context.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/app_keys.dart';
import '../app_icon_button.dart';
import '../file_tree_node.dart';
import 'file_tree_header_overflow_menu.dart';

const _fileTreeRowPadding = EdgeInsets.symmetric(
  horizontal: kFileTreeRowHorizontalPadding,
  vertical: kFileTreeRowVerticalPadding,
);

/// Workspace file tree panel.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({required this.cwd, this.watcher, super.key});

  final String cwd;

  /// Shared workspace watcher; when present, the tree refreshes live on disk
  /// changes. Null on backends without watch support (the tree stays manual).
  final WorkspaceFsWatcher? watcher;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  final _cubit = FileTreeCubit(fs: AppStorage.fs);
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  EditorCubit? _editorCubit;
  StreamSubscription<void>? _watchSub;

  @override
  void initState() {
    super.initState();
    _syncRoot();
    _subscribeWatcher();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _editorCubit = context.read<EditorCubit>();
  }

  @override
  void didUpdateWidget(covariant FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd) {
      _syncRoot();
    }
    if (!identical(widget.watcher, oldWidget.watcher)) {
      _subscribeWatcher();
    }
  }

  void _syncRoot() {
    _cubit.setRoot(widget.cwd);
  }

  void _subscribeWatcher() {
    _watchSub?.cancel();
    _watchSub = widget.watcher?.onChanged.listen((changedDirs) {
      // Empty set = unknown scope (e.g. a terminal turn-end poke) → full
      // refresh; otherwise reload only the directories that actually changed.
      if (changedDirs.isEmpty) {
        unawaited(_cubit.refresh());
      } else {
        unawaited(_cubit.refreshPaths(changedDirs));
      }
    });
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

      final rows = visibleFileTreeRows(
        state: _cubit.state,
        pathContext: _cubit.fs.pathContext,
      );
      final index = visibleRowIndexForPath(rows, target, _cubit.fs.pathContext);
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
    _watchSub?.cancel();
    _filterController.dispose();
    _listScrollController.dispose();
    _horizontalScrollController.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FileTreeCubit, FileTreeState>(
        builder: (context, state) {
          return Container(
            key: AppKeys.fileTreePanel,
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const actionSlotWidth = 28.0;
                    final hasExpandedFolders = state.expandedPaths.isNotEmpty;
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
                            state: state,
                          )
                        else
                          FileTreeHeaderOverflowMenu(
                            l10n: l10n,
                            showHiddenFiles: state.showHiddenFiles,
                            hasExpandedFolders: hasExpandedFolders,
                            canCopy: state.rootPath.isNotEmpty,
                            onRefresh: _cubit.refresh,
                            onReveal: () =>
                                unawaited(_revealActiveEditorFile()),
                            onCollapseAll: _cubit.collapseAllFolders,
                            onToggleHidden: _cubit.toggleShowHidden,
                            onCopy: () {
                              if (state.rootPath.isNotEmpty) {
                                Clipboard.setData(
                                  ClipboardData(text: state.rootPath),
                                );
                              }
                            },
                          ),
                      ],
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
                                  compact: true, size: AppIconButton.kCompactSize,
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
                      if (state.rootExists)
                        Text(
                          state.rootPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(
                            context,
                          ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        Text(
                          'Directory unavailable',
                          style: AppTextStyles.of(context).bodySmall.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: state.rootExists
                            ? _buildFileList(state, cs.onSurface)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildFileTreeHeaderActions({
    required AppLocalizations l10n,
    required FileTreeState state,
  }) {
    final actions = <Widget>[
      AppIconButton(
        icon: Icons.refresh,
        compact: true, size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRefresh,
        onTap: _cubit.refresh,
      ),
      AppIconButton(
        icon: Icons.my_location_outlined,
        compact: true, size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
    ];
    if (state.expandedPaths.isNotEmpty) {
      actions.add(
        AppIconButton(
          icon: Icons.unfold_less,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.treeCollapseAllFolders,
          onTap: _cubit.collapseAllFolders,
        ),
      );
    }
    actions.addAll([
      AppIconButton(
        icon: state.showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        compact: true, size: AppIconButton.kCompactSize,
        tooltip: state.showHiddenFiles
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
          if (state.rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: state.rootPath));
          }
        },
      ),
    ]);
    return actions;
  }

  Widget _buildFileList(FileTreeState state, Color textColor) {
    final rows = visibleFileTreeRows(
      state: state,
      pathContext: _cubit.fs.pathContext,
    );
    if (rows.isEmpty) {
      return Text(
        '(empty)',
        style: AppTextStyles.of(
          context,
        ).bodySmall.copyWith(color: textColor.withValues(alpha: 0.35)),
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
          controller: _horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _listScrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _listScrollController,
                  itemCount: rows.length,
                  itemExtent: kFileTreeRowExtent,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.isEmptyPlaceholder) {
                      return SizedBox(
                        width: contentWidth,
                        child: Padding(
                          padding: _fileTreeRowPadding,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left:
                                    row.depth * kFileTreeIndentWidth +
                                    kFileTreeNodePaddingLeft +
                                    18,
                              ),
                              child: Text(
                                '(empty)',
                                style: AppTextStyles.of(context).caption
                                    .copyWith(
                                      color: textColor.withValues(alpha: 0.35),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return SizedBox(
                      width: contentWidth,
                      child: Padding(
                        padding: _fileTreeRowPadding,
                        child: FileTreeNode(
                          path: row.path,
                          entry: row.entry,
                          depth: row.depth,
                          cubit: _cubit,
                          textColor: textColor,
                          desktopShellActions: _desktopShellActions,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _desktopShellActions {
    if (kIsWeb) return false;
    final mode = AppStorage.context.mode;
    return mode == StorageBackendMode.native ||
        mode == StorageBackendMode.wsl;
  }
}
