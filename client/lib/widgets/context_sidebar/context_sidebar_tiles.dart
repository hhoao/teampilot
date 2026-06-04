part of '../context_sidebar.dart';

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.sidebarSettingsButton,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.tune_outlined, size: AppIconSizes.md, color: textBase),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamConfigTile extends StatelessWidget {
  const _TeamConfigTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.groups_2_outlined, size: AppIconSizes.md, color: textBase),
              const SizedBox(width: 10),
              Text(context.l10n.teamConfig),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewChatTile extends StatelessWidget {
  const _NewChatTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.newChatSidebarTile,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: AppIconSizes.md, color: textBase),
              const SizedBox(width: 10),
              Text(context.l10n.defaultNewChatSessionTitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({
    required this.teams,
    required this.selected,
    required this.onSelect,
    this.onAddTeam,
  });

  final List<TeamConfig> teams;
  final TeamConfig selected;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAddTeam;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final decoration = AppDropdownDecorations.themed(
      context,
      closedFillColor: cs.workspaceCard,
      expandedFillColor: cs.workspaceCard,
      borderRadius: 8,
      headerFontWeight: FontWeight.w700,
      listItemFontWeight: FontWeight.w600,
      suffixIconSize: AppIconSizes.md,
      expandedShadowBlurRadius: 22,
      expandedShadowOffset: const Offset(0, 10),
      expandedShadowAlphaDark: 0.5,
      expandedShadowAlphaLight: 0.12,
      selectedPrimaryAlphaDark: 0.22,
    );

    return Container(
      margin: const EdgeInsets.only(top: 14),
      // InputDecorator below the closed header adds invisible height; top-align
      // a fixed-size add button with the visible field instead of stretching it.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppDropdownField<TeamConfig>(
              items: teams,
              initialItem: selected,
              hintText: l10n.selectTeam,
              decoration: decoration,
              itemLabel: (team) => team.name,
              onChanged: (team) {
                if (team != null && team.id != selected.id) {
                  onSelect(team.id);
                }
              },
            ),
          ),
          if (onAddTeam != null) ...[
            const SizedBox(width: 6),
            AppIconButton(
              icon: Icons.add,
              tooltip: l10n.addTeamTooltip,
              onTap: onAddTeam,
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  // ignore: unused_element_parameter
  const _SidebarTile({
    required this.title,
    required this.selected,
    // ignore: unused_element_parameter
    this.subtitle = '',
    this.rowHovered = false,
    this.onTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.trailing,
    this.contentLeftInset = 0,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;

  /// From parent [MouseRegion] (and menu-open), not [InkWell] — avoids ink
  /// fighting with the overflow menu (hover patch only behind title).
  final bool rowHovered;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Extra left padding so row text lines up with folder names (file tree).
  final double contentLeftInset;

  Color _materialFillColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    if (selected) {
      return rowHovered
          ? Color.alphaBlend(hoverTint, cs.primaryContainer)
          : cs.primaryContainer;
    }
    if (rowHovered) {
      return Color.alphaBlend(hoverTint, cs.surfaceContainer);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: _materialFillColor(context),
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onLongPress: onLongPress,
          child: Container(
            padding: EdgeInsets.fromLTRB(8 + contentLeftInset, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected ? Border.all(color: cs.primaryContainer) : null,
            ),
            // Do not use [CrossAxisAlignment.stretch] here: [_SidebarTile] is used
            // inside [ListView] items, which get an unbounded max height on the main
            // axis; stretch would force children to infinite height and assert.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.of(context).caption.copyWith(
                                color: textBase.withValues(alpha: 0.52),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
