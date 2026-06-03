import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/team_pilot_brand_logo.dart';
import 'home_workspace_project_section.dart';

/// Narrow vertical icon rail on the left of the project page (mirrors Apifox's
/// 接口管理 / 自动化测试 / … rail).
class HomeWorkspaceProjectRail extends StatelessWidget {
  const HomeWorkspaceProjectRail({
    required this.brandColor,
    required this.section,
    required this.onSectionChanged,
    required this.onLogoTap,
    super.key,
  });

  final Color brandColor;
  final HomeWorkspaceProjectSection section;
  final ValueChanged<HomeWorkspaceProjectSection> onSectionChanged;
  final VoidCallback onLogoTap;

  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          const SizedBox(height: 10),
          _RailItem(
            icon: Icons.forum_outlined,
            label: l10n.homeWorkspaceConversations,
            active: section == HomeWorkspaceProjectSection.conversations,
            onTap: () => onSectionChanged(
              HomeWorkspaceProjectSection.conversations,
            ),
          ),
          _RailItem(
            icon: Icons.settings_outlined,
            label: l10n.homeWorkspaceProjectSettings,
            active: section == HomeWorkspaceProjectSection.settings,
            onTap: () => onSectionChanged(HomeWorkspaceProjectSection.settings),
          ),
          const Spacer(),
          _RailItem(
            label: l10n.appTitle,
            active: false,
            onTap: onLogoTap,
            child: TeamPilotBrandLogo(size: 24, gradientStart: brandColor),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.child,
  }) : assert(icon != null || child != null);

  final IconData? icon;
  final Widget? child;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                if (active)
                  Container(
                    width: 3,
                    height: 36,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active || !_hovered
                          ? Colors.transparent
                          : cs.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child:
                        widget.child ??
                        Icon(widget.icon, size: AppIconSizes.md, color: fg),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
