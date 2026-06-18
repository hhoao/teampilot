import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/identity_cubit.dart';
import '../../../../cubits/skill_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_skills_section.dart';

class ProjectSkillsSection extends StatelessWidget {
  const ProjectSkillsSection({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<IdentityCubit>().activePersonal;
    if (personal == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = context.l10n;
    void onManage() =>
        context.go(HomeWorkspaceGlobalView.skills.homeLocation);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final skillState = context.watch<SkillCubit>().state;
    final enabled = skillState.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final skillIds = personal.bundle.skillIds;
    final assignedCount =
        enabled.where((s) => skillIds.contains(s.id)).length;
    final cubit = context.read<IdentityCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.projectSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.extension_outlined),
                    label: Text(l10n.projectSkillsManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  TeamSkillsEmptyBlock(
                    textBase: textBase,
                    onGoSkills: onManage,
                    manageButtonLabel: l10n.projectSkillsManage,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final skill in enabled)
                        TeamSkillRow(
                          skill: skill,
                          assigned: skillIds.contains(skill.id),
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(skillIds);
                            if (assigned) {
                              if (!ids.contains(skill.id)) ids.add(skill.id);
                            } else {
                              ids.remove(skill.id);
                            }
                            cubit.setActivePersonalSkillIds(ids);
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
