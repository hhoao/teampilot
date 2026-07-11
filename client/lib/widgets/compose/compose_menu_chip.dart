import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../menu/sidebar_action_menu.dart';

/// Popover menu chip matching landing compose toolbar visuals.
class ComposeMenuChip extends StatelessWidget {
  const ComposeMenuChip({
    required this.palette,
    required this.icon,
    required this.label,
    required this.specs,
    required this.onSelected,
    this.minWidth = 200,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final IconData icon;
  final String label;
  final List<SidebarActionMenuSpec> specs;
  final ValueChanged<Object?> onSelected;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return SidebarActionMenuIconAnchor(
      minWidth: minWidth,
      triggerBuilder: (context, controller) => ComposeToolbarChip(
        palette: palette,
        icon: icon,
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
          buildSidebarActionMenuChildren(
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
    this.onTap,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final icons = context.appIconSizes;
    final labelStyle = AppTextStyles.of(
      context,
    ).bodySmall.copyWith(color: palette.muted, fontWeight: FontWeight.w500);

    return Material(
      color: palette.chipFill,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                Icon(icon, size: icons.sm, color: palette.muted),
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
      ),
    );
  }
}
