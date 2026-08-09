import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/git_cubit.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import 'git_context_menu.dart';

/// Folder row in the git changes tree view. IDEA-style: a tri-state stage
/// checkbox, chevron toggle on click, context menu on right-click.
class GitChangeFolderTile extends StatelessWidget {
  const GitChangeFolderTile({
    required this.folderPath,
    required this.name,
    required this.depth,
    required this.subtreeSelectedCount,
    required this.subtreeTotalCount,
    required this.cubit,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscardFolder,
    this.hoverEnabled = true,
    super.key,
  });

  final String folderPath;
  final String name;
  final int depth;
  final int subtreeSelectedCount;
  final int subtreeTotalCount;
  final GitCubit cubit;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscardFolder;
  final bool hoverEnabled;

  bool? get _triState =>
      subtreeTotalCount == 0
          ? false
          : subtreeSelectedCount == subtreeTotalCount
          ? true
          : subtreeSelectedCount == 0
          ? false
          : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = context.select<GitCubit, bool>(
      (c) => c.state.expandedFolderPaths.contains(folderPath),
    );

    return RepaintBoundary(
      child: TpHover(
        onTap: () => cubit.toggleFolderExpanded(folderPath),
        onSecondaryTapDown: (details) => unawaited(
          GitFolderContextMenu.show(
            context: context,
            tapDetails: details,
            folderPath: folderPath,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscardFolder: onDiscardFolder,
          ),
        ),
        hoverColor: hoverEnabled ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          depth * kGitChangesIndentWidth +
              kGitChangesNodePaddingLeft +
              kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
          kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
        ),
        child: SizedBox(
          width: double.infinity,
          height: kGitChangesNodeHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: kGitChangesCheckboxWidth,
                height: kGitChangesCheckboxWidth,
                child: Checkbox(
                  value: _triState,
                  tristate: true,
                  onChanged: (_) => _triState == true
                      ? onUnstage()
                      : onStage(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.folder_open : Icons.folder_outlined,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
