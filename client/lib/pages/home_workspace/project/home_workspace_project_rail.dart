import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../theme/app_text_styles.dart';

/// Narrow vertical icon rail on the left of the project page (mirrors Apifox's
/// 接口管理 / 自动化测试 / … rail). The active item is "Conversations".
class HomeWorkspaceProjectRail extends StatelessWidget {
  const HomeWorkspaceProjectRail({
    required this.brandColor,
    required this.onInvite,
    super.key,
  });

  final Color brandColor;
  final VoidCallback onInvite;

  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _RailItem(
            icon: Icons.forum_outlined,
            label: l10n.homeWorkspaceConversations,
            active: true,
            onTap: () {},
          ),
          _RailItem(
            icon: Icons.settings_outlined,
            label: l10n.homeWorkspaceProjectSettings,
            active: false,
            onTap: () => _comingSoon(context),
          ),
          const Spacer(),
          _RailItem(
            icon: Icons.person_add_alt_1_outlined,
            label: l10n.homeWorkspaceInviteMembers,
            active: false,
            onTap: onInvite,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.homeWorkspaceComingSoon)),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
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
    final styles = AppTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? cs.primary.withValues(alpha: 0.14)
                : _hovered
                    ? cs.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(widget.icon, size: 20, color: fg),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: styles.caption.copyWith(
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
