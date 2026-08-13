// client/lib/widgets/compose/compose_paste_clip_bar.dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../services/compose/compose_clip.dart';

/// Compact bar shown above the compose field when an oversized paste has been
/// collapsed into a [ComposeClip]: a "Pasted text · N lines" badge plus a
/// remove affordance. Clicking the badge opens the full editor.
class ComposePasteClipBar extends StatelessWidget {
  const ComposePasteClipBar({
    required this.clip,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final ComposeClip clip;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final icons = context.tpIconSizes;
    final styles = TpTextStyles.of(context);
    final label =
        '${l10n.composePasteClipLabel} · ${l10n.composePasteClipLines(clip.lineCount)}';

    final badge = Material(
      color: palette.chipFill,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.content_paste_rounded,
                size: icons.sm,
                color: palette.muted,
              ),
              SizedBox(width: spacing.xs),
              Text(label, style: styles.smColored(palette.muted)),
              SizedBox(width: spacing.xs),
              Icon(
                Icons.open_in_full,
                size: icons.sm,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(message: l10n.composePasteClipEdit, child: badge),
        SizedBox(width: spacing.xs),
        Tooltip(
          message: l10n.composePasteClipRemove,
          child: TpHover(
            shape: TpPressableShape.circle,
            width: 28,
            height: 28,
            backgroundColor: Colors.transparent,
            onTap: onRemove,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: icons.sm,
                color: palette.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
