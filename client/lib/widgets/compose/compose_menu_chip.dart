import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
/// Popover menu chip matching landing compose toolbar visuals.
class ComposeMenuChip extends StatelessWidget {
  const ComposeMenuChip({
    required this.palette,
    required this.icon,
    required this.label,
    required this.specs,
    required this.onSelected,
    this.leading,
    this.minWidth = 200,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final IconData icon;
  final String label;
  final List<TpActionMenuSpec> specs;
  final ValueChanged<Object?> onSelected;
  final Widget? leading;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return TpActionMenuIconAnchor(
      minWidth: minWidth,
      triggerBuilder: (context, controller) => ComposeToolbarChip(
        palette: palette,
        icon: icon,
        leading: leading,
        label: label,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      buildMenuChildren: (context, controller) =>
          buildTpActionMenuChildren(
            context: context,
            specs: specs,
            menuController: controller,
            onSelect: onSelected,
          ),
    );
  }
}

/// Stadium chip trigger used by [ComposeMenuChip].
class ComposeToolbarChip extends StatelessWidget {
  const ComposeToolbarChip({
    required this.palette,
    required this.icon,
    required this.label,
    this.leading,
    this.onTap,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final IconData icon;
  final String label;
  final Widget? leading;
  final VoidCallback? onTap;

  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final icons = context.tpIconSizes;
    final labelStyle = TpTextStyles.of(
      context,
    ).smColored(palette.muted);

    return TpHover(
      backgroundColor: palette.chipFill,
      shape: TpPressableShape.stadium,
      border: Border.all(color: palette.border),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading ?? Icon(icon, size: icons.sm, color: palette.muted),
              SizedBox(width: spacing.xs),
              Text(label, style: labelStyle),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: icons.md,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
