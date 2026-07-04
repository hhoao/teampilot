import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/launch_profile_kind.dart';
import '../../../models/team_config.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';

/// Manage-panel profile switcher — driven by route `?profile=`, not compose landing.
class WorkspaceProfileIdentityBar extends StatelessWidget {
  const WorkspaceProfileIdentityBar({
    required this.selectedProfileId,
    required this.onProfileSelected,
    super.key,
  });

  final String selectedProfileId;
  final ValueChanged<String> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final launchProfiles = context.watch<LaunchProfileCubit>();
    final personal = launchProfiles.activePersonal;
    final teams = launchProfiles.state.teams;
    final selected = launchProfiles.byId(selectedProfileId);
    final isPersonal = selected?.kind == LaunchProfileKind.personal;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, spacing.md, spacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.homeWorkspaceWorkspaceManagement,
            style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              if (personal != null)
                _ProfileChip(
                  label: l10n.workspaceChatLandingModeSimple,
                  icon: Icons.person_outline,
                  selected: isPersonal == true,
                  onTap: () => onProfileSelected(personal.id),
                ),
              for (final team in teams)
                _ProfileChip(
                  label: team.name,
                  icon: Icons.groups_outlined,
                  selected: isPersonal != true && selectedProfileId == team.id,
                  onTap: () => _selectTeam(context, team),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectTeam(BuildContext context, TeamProfile team) {
    unawaited(
      context.read<LaunchProfileCubit>().selectTeam(team.id, silent: true),
    );
    onProfileSelected(team.id);
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final fg = selected ? cs.primary : cs.onSurfaceVariant;
    final bg = selected
        ? cs.primaryContainer.withValues(alpha: 0.35)
        : cs.surfaceContainerHighest.withValues(alpha: 0.5);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: context.appIconSizes.sm, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: styles.bodySmall.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
