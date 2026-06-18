import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/skill_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_config_cards.dart';

class TeamSkillsSection extends StatelessWidget {
  const TeamSkillsSection({
    super.key,
    required this.team,
    required this.cubit,
    this.onManageGlobal,
  });

  final TeamIdentity team;
  final TeamCubit cubit;

  /// Opens global skill management. When null, falls back to the v1
  /// `/skills` route so this section stays usable outside the v2 workspace.
  final VoidCallback? onManageGlobal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onManage = onManageGlobal ?? () => context.go('/skills');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final skillState = context.watch<SkillCubit>().state;
    final enabled = skillState.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final assignedCount = enabled
        .where((s) => team.skillIds.contains(s.id))
        .length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.teamSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.extension_outlined, size: context.appIconSizes.md),
                    label: Text(l10n.teamSkillsManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  TeamSkillsEmptyBlock(
                    textBase: textBase,
                    onGoSkills: onManage,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final skill in enabled)
                        TeamSkillRow(
                          skill: skill,
                          assigned: team.skillIds.contains(skill.id),
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(team.skillIds);
                            if (assigned) {
                              if (!ids.contains(skill.id)) ids.add(skill.id);
                            } else {
                              ids.remove(skill.id);
                            }
                            cubit.updateSelected(team.copyWith(skillIds: ids));
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TeamSkillsEmptyBlock extends StatelessWidget {
  const TeamSkillsEmptyBlock({super.key,
    required this.textBase,
    required this.onGoSkills,
    this.manageButtonLabel,
  });

  final Color textBase;
  final VoidCallback onGoSkills;
  final String? manageButtonLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: context.appIconSizes.md,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.skillsNoInstalled,
            style: AppTextStyles.of(
              context,
            ).body.copyWith(fontWeight: FontWeight.w700, color: textBase),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.skillsNoInstalledHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.of(
              context,
            ).bodySmall.copyWith(color: textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onGoSkills,
            icon: Icon(Icons.extension_outlined, size: context.appIconSizes.md),
            label: Text(manageButtonLabel ?? l10n.teamSkillsManage),
          ),
        ],
      ),
    );
  }
}

class TeamSkillRow extends StatelessWidget {
  const TeamSkillRow({super.key, 
    required this.skill,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final Skill skill;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final sourceLabel = skill.repoOwner != null && skill.repoName != null
        ? '${skill.repoOwner}/${skill.repoName}'
        : l10n.skillsLocal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          skill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(context).body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: textBase,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: textBase.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (skill.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GithubDetailsButton(
              url: skill.githubBrowseUrl,
              label: l10n.skillsCardDetails,
            ),
            const SizedBox(width: 8),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}
