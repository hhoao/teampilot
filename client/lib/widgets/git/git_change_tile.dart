import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import '../file_icon_widget.dart';

/// One changed file row in the source control changes tree.
///
/// Shows a status badge + file name; trailing actions depend on the area:
/// staged rows offer "unstage", unstaged rows offer "discard" + "stage".
/// Tapping the row opens the diff.
class GitChangeTile extends StatefulWidget {
  const GitChangeTile({
    required this.change,
    required this.depth,
    required this.onOpenDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.onOpenFile,
    this.hoverEnabled = true,
    super.key,
  });

  final GitFileChange change;
  final int depth;
  final VoidCallback onOpenDiff;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final VoidCallback? onOpenFile;
  final bool hoverEnabled;

  @override
  State<GitChangeTile> createState() => _GitChangeTileState();
}

class _GitChangeTileState extends State<GitChangeTile> {
  var _hovered = false;

  @override
  void didUpdateWidget(covariant GitChangeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hoverEnabled && _hovered) {
      _hovered = false;
    }
  }

  Color _badgeColor(ColorScheme cs) => switch (widget.change.kind) {
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
    final change = widget.change;
    final name = p.basename(change.path);

    return RepaintBoundary(
      child: TpHover(
        onTap: widget.onOpenDiff,
        hoverColor: widget.hoverEnabled ? null : Colors.transparent,
        onHoverChanged: (hovered) {
          if (!widget.hoverEnabled) return;
          setState(() => _hovered = hovered);
        },
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          widget.depth * kGitChangesIndentWidth +
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
              const SizedBox(width: 16),
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
              if (_hovered) ..._actions(context) else _badge(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(ColorScheme cs) => SizedBox(
    width: kGitChangesTrailingBadgeWidth,
    child: Text(
      widget.change.badge,
      textAlign: TextAlign.center,
      style: TpTextStyles.of(
        context,
      ).smBoldColored(_badgeColor(cs)),
    ),
  );

  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final actions = <Widget>[
      if (widget.change.staged)
        TpIconButton(
          icon: Icons.remove,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitUnstage,
          onTap: widget.onUnstage,
        )
      else ...[
        TpIconButton(
          icon: Icons.undo,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitDiscard,
          onTap: widget.onDiscard,
        ),
        TpIconButton(
          icon: Icons.add,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitStage,
          onTap: widget.onStage,
        ),
      ],
      if (widget.onOpenFile != null)
        TpIconButton(
          icon: Icons.file_open_outlined,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.gitOpenFile,
          onTap: widget.onOpenFile,
        ),
    ];
    return actions;
  }
}
