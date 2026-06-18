import 'package:flutter/material.dart';

import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../l10n/l10n_extensions.dart';

class HomeTeamHeader extends StatelessWidget {
  const HomeTeamHeader({super.key, required this.team});

  final TeamProfile team;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(color: cs.onSurface);
    final isMixed = team.teamMode == TeamMode.mixed;
    final modeLabel = isMixed ? l10n.teamModeMixedTitle : l10n.teamModeNativeTitle;
    final badgeColor = isMixed ? cs.tertiary : cs.primary;
    return Row(
      children: [
        Text(team.name, style: titleStyle),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            modeLabel,
            style: styles.caption.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class HomeContentTabBar extends StatelessWidget {
  const HomeContentTabBar({super.key, 
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            HomeContentTabItem(
              label: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class HomeContentTabItem extends StatefulWidget {
  const HomeContentTabItem({super.key, 
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<HomeContentTabItem> createState() => HomeContentTabItemState();
}

class HomeContentTabItemState extends State<HomeContentTabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.transparent
                  : _hovered
                  ? cs.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.prominent.copyWith(
                color: selected
                    ? cs.primary
                    : _hovered
                    ? cs.onSurface
                    : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
