import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
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
    this.hoverEnabled,
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

  /// Whether the hover highlight is live. A listenable because it flips while
  /// the list scrolls — listeners rebuild only the hover surface, not the row.
  /// Null (default) keeps hover always on.
  final ValueListenable<bool>? hoverEnabled;

  /// Shared always-on listenable for tiles constructed without [hoverEnabled].
  static final ValueListenable<bool> _hoverAlwaysOn = ValueNotifier<bool>(true);

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

    // Row content is hoisted so a hover flip (scroll start/end) rebuilds only
    // the TpHover surface below, never this subtree.
    final rowContent = SizedBox(
      width: double.infinity,
      height: kGitChangesNodeHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: kGitChangesChevronWidth,
            height: 16,
            // Flush the 16px glyph to the left edge of the 18px column so
            // it aligns with the parent folder's checkbox left edge.
            child: Align(
              alignment: Alignment.centerLeft,
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
          ),
          SizedBox(
            width: kGitChangesCheckboxColumnWidth,
            height: kGitChangesCheckboxWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kGitChangesCheckboxHPadding,
              ),
              child: Checkbox(
                value: _triState,
                tristate: true,
                onChanged: (_) => _triState == true
                    ? onUnstage()
                    : onStage(),
                visualDensity: VisualDensity.compact,
              ),
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
    );

    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: hoverEnabled ?? _hoverAlwaysOn,
        child: rowContent,
        builder: (context, hoverOn, child) => TpHover(
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
          hoverColor: hoverOn ? null : Colors.transparent,
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
          child: child!,
        ),
      ),
    );
  }
}
