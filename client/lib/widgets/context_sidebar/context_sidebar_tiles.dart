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
              Icon(
                Icons.groups_2_outlined,
                size: AppIconSizes.md,
                color: textBase,
              ),
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
              size: 42,
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
