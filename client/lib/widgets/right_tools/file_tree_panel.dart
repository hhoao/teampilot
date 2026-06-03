import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/file_tree/file_tree_visible_rows.dart';
import '../../services/storage/app_storage.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/app_keys.dart';
import '../app_icon_button.dart';
import '../file_tree_node.dart';
import 'file_tree_header_overflow_menu.dart';

/// Project file tree panel.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    required this.team,
    required this.cwd,
    super.key,
  });

  final TeamConfig team;
  final String cwd;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  final _cubit = FileTreeCubit(fs: AppStorage.fs);
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();
  EditorCubit? _editorCubit;

  @override
  void initState() {
    super.initState();
    _syncRoot();
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
  }

  void _syncRoot() {
    _cubit.setRoot(widget.cwd);
  }

  Future<void> _revealActiveEditorFile() async {
    if (!mounted) return;
    final active = _editorCubit?.state.activePath;
    if (active == null) return;

    _filterController.clear();
    final ok = await _cubit.revealPath(active);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fileTreeRevealFailed)),
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
    _filterController.dispose();
    _listScrollController.dispose();
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
                    final showInlineActions =
                        constraints.maxWidth >= actionSlotWidth * 3;
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
                          BlocBuilder<LayoutCubit, LayoutState>(
                            buildWhen: (previous, next) =>
                                previous.preferences.workspaceTerminalVisible !=
                                next.preferences.workspaceTerminalVisible,
                            builder: (context, layoutState) {
                              final terminalVisible = layoutState
                                  .preferences
                                  .workspaceTerminalVisible;
                              return FileTreeHeaderOverflowMenu(
                                l10n: l10n,
                                workspaceTerminalVisible: terminalVisible,
                                showHiddenFiles: state.showHiddenFiles,
                                canCopy: state.rootPath.isNotEmpty,
                                onToggleTerminal: () => context
                                    .read<LayoutCubit>()
                                    .setWorkspaceTerminalVisible(
                                      !terminalVisible,
                                    ),
                                onReveal: () =>
                                    unawaited(_revealActiveEditorFile()),
                                onToggleHidden: _cubit.toggleShowHidden,
                                onCopy: () {
                                  if (state.rootPath.isNotEmpty) {
                                    Clipboard.setData(
                                      ClipboardData(text: state.rootPath),
                                    );
                                  }
                                },
                              );
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
                          prefixIcon: const Icon(Icons.search, size: AppIconSizes.md),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          suffixIcon: _filterController.text.isNotEmpty
                              ? AppIconButton(
                                  icon: Icons.clear,
                                  iconSize: AppIconButton.kCompactIconSize,
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
                            fontStyle: FontStyle.italic,
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
    return [
      BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (previous, next) =>
            previous.preferences.workspaceTerminalVisible !=
            next.preferences.workspaceTerminalVisible,
        builder: (context, layoutState) {
          final visible = layoutState.preferences.workspaceTerminalVisible;
          return AppIconButton(
            icon: visible ? Icons.terminal : Icons.terminal_outlined,
            iconSize: AppIconButton.kCompactIconSize,
            size: AppIconButton.kCompactSize,
            tooltip: visible
                ? l10n.workspaceTerminalHide
                : l10n.workspaceTerminalShow,
            onTap: () => context
                .read<LayoutCubit>()
                .setWorkspaceTerminalVisible(!visible),
          );
        },
      ),
      AppIconButton(
        icon: Icons.my_location_outlined,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
      AppIconButton(
        icon: state.showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: state.showHiddenFiles
            ? 'Hide hidden files'
            : 'Show hidden files',
        onTap: _cubit.toggleShowHidden,
      ),
      AppIconButton(
        icon: Icons.copy,
        iconSize: AppIconSizes.md,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.copy,
        onTap: () {
          if (state.rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: state.rootPath));
          }
        },
      ),
    ];
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
    return ListView.builder(
      controller: _listScrollController,
      itemCount: rows.length,
      itemExtent: kFileTreeRowExtent,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isEmptyPlaceholder) {
          return SizedBox(
            height: kFileTreeRowExtent,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: row.depth * 16 + 22),
                child: Text(
                  '(empty)',
                  style: AppTextStyles.of(
                    context,
                  ).caption.copyWith(color: textColor.withValues(alpha: 0.35)),
                ),
              ),
            ),
          );
        }
        return FileTreeNode(
          path: row.path,
          entry: row.entry,
          depth: row.depth,
          cubit: _cubit,
          textColor: textColor,
        );
      },
    );
  }
}
