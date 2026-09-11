import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Dual-segment Edit|Preview toggle shared by the HTML and SVG editor
/// toolbars. Selection state is caller-owned.
class EditorViewModeToggle extends StatelessWidget {
  const EditorViewModeToggle({
    required this.editSelected,
    required this.previewSelected,
    required this.onEditTap,
    required this.onPreviewTap,
    super.key,
  });

  final bool editSelected;
  final bool previewSelected;
  final VoidCallback onEditTap;
  final VoidCallback onPreviewTap;

  static const double _size = TpIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = cs.tpIconMuted;
    return Container(
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.code,
            tooltip: l10n.htmlViewToggleEdit,
            selected: editSelected,
            color: color,
            onTap: onEditTap,
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _Segment(
            icon: Icons.visibility_outlined,
            tooltip: l10n.htmlViewTogglePreview,
            selected: previewSelected,
            color: color,
            onTap: onPreviewTap,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        backgroundColor: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.zero,
        width: 30,
        height: EditorViewModeToggle._size,
        hoverColor: color.withValues(alpha: 0.12),
        splashColor: color.withValues(alpha: 0.2),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: context.tpIconSizes.sm, color: color),
        ),
      ),
    );
  }
}
