import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';

import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../file_icon_widget.dart';
import 'git_context_menu.dart';

/// One changed file row in the source control changes tree.
///
/// IDEA-style: a stage checkbox on the left (checked = staged), a status
/// badge on the right, single-click selects + opens the diff, double-click
/// opens the file, right-click shows the context menu.
class GitChangeTile extends StatelessWidget {
  const GitChangeTile({
    required this.change,
    required this.depth,
    required this.selected,
    required this.onSelect,
    required this.onOpenDiff,
    this.onOpenFile,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.hoverEnabled,
    super.key,
  });

  final GitFileChange change;
  final int depth;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpenDiff;
  final VoidCallback? onOpenFile;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;

  /// Whether the hover highlight is live. A listenable because it flips while
  /// the list scrolls — listeners rebuild only the hover surface, not the row.
  /// Null (default) keeps hover always on.
  final ValueListenable<bool>? hoverEnabled;

  /// Shared always-on listenable for tiles constructed without [hoverEnabled].
  static final ValueListenable<bool> _hoverAlwaysOn = ValueNotifier<bool>(true);

  Color _badgeColor(ColorScheme cs) => switch (change.kind) {
    GitChangeKind.added => const Color(0xFF2EA043),
    GitChangeKind.untracked => const Color(0xFF2EA043),
    GitChangeKind.deleted => cs.error,
    GitChangeKind.conflicted => cs.error,
    GitChangeKind.renamed => cs.primary,
    GitChangeKind.modified => const Color(0xFFB58900),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = p.basename(change.path);

    // Row content is hoisted so a hover flip (scroll start/end) rebuilds only
    // the TpHover surface below, never this subtree.
    final rowContent = SizedBox(
      width: double.infinity,
      height: kGitChangesNodeHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: kGitChangesCheckboxColumnWidth,
            height: kGitChangesCheckboxWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kGitChangesCheckboxHPadding,
              ),
              child: Checkbox(
                value: change.staged,
                onChanged: (_) => change.staged ? onUnstage() : onStage(),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FileIconWidget(fileName: name),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).md,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: kGitChangesTrailingBadgeWidth,
            child: Text(
              change.badge,
              textAlign: TextAlign.center,
              style: TpTextStyles.of(context).smBoldColored(_badgeColor(cs)),
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
          onTap: onSelect,
          onDoubleTap: onOpenFile,
          onSecondaryTapDown: (details) => unawaited(
            GitFileContextMenu.show(
              context: context,
              tapDetails: details,
              staged: change.staged,
              path: change.path,
              onOpenFile: onOpenFile,
              onOpenDiff: onOpenDiff,
              onStage: onStage,
              onUnstage: onUnstage,
              onDiscard: onDiscard,
            ),
          ),
          hoverColor: hoverOn ? null : Colors.transparent,
          backgroundColor: selected ? cs.secondaryContainer : null,
          borderRadius: BorderRadius.circular(6),
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(
            depth * kGitChangesIndentWidth +
                kGitChangesChevronWidth +
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
