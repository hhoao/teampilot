import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';

/// One changed file row in the source control panel.
///
/// Shows a status badge + file name; trailing actions depend on the area:
/// staged rows offer "unstage", unstaged rows offer "discard" + "stage".
/// Tapping the row opens the diff.
class GitChangeTile extends StatefulWidget {
  const GitChangeTile({
    required this.change,
    required this.onOpenDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    super.key,
  });

  final GitFileChange change;
  final VoidCallback onOpenDiff;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;

  @override
  State<GitChangeTile> createState() => _GitChangeTileState();
}

class _GitChangeTileState extends State<GitChangeTile> {
  var _hovered = false;

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
    final l10n = context.l10n;
    final change = widget.change;
    final name = p.basename(change.path);
    final dir = p.dirname(change.path);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onOpenDiff,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              const SizedBox(width: 2),
              Icon(
                change.kind == GitChangeKind.untracked
                    ? Icons.insert_drive_file_outlined
                    : Icons.description_outlined,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.of(context).bodySmall,
                      ),
                    ),
                    if (dir != '.' && dir.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(context).caption.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_hovered) ..._actions(l10n) else _badge(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(ColorScheme cs) => SizedBox(
    width: 22,
    child: Text(
      widget.change.badge,
      textAlign: TextAlign.center,
      style: AppTextStyles.of(context).bodySmall.copyWith(
        color: _badgeColor(cs),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  List<Widget> _actions(AppLocalizations l10n) {
    if (widget.change.staged) {
      return [
        AppIconButton(
          icon: Icons.remove,
          iconSize: AppIconButton.kCompactIconSize,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitUnstage,
          onTap: widget.onUnstage,
        ),
      ];
    }
    return [
      AppIconButton(
        icon: Icons.undo,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.gitDiscard,
        onTap: widget.onDiscard,
      ),
      AppIconButton(
        icon: Icons.add,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.gitStage,
        onTap: widget.onStage,
      ),
    ];
  }
}
