import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/skill_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../home_workspace_global_section.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_skills_section.dart';
import 'package:shared_ui/shared_ui.dart';

class WorkspaceSkillsSection extends StatelessWidget {
  const WorkspaceSkillsSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    void onManage() => context.go(HomeGlobalView.skills.homeLocation);
    final skillState = context.watch<SkillCubit>().state;
    final enabled = skillState.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final skillIds = projectState.config.bundle.skillIds;
    final assignedCount = enabled.where((s) => skillIds.contains(s.id)).length;
    final projectCubit = context.read<WorkspaceProjectConfigCubit>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.workspaceSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: Icon(Icons.extension_outlined),
                    label: Text(l10n.workspaceSkillsManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  TpEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.skillsNoInstalled,
                    hint: l10n.skillsNoInstalledHint,
                    actionLabel: l10n.workspaceSkillsManage,
                    onAction: onManage,
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
                            unawaited(
                              projectCubit.updateBundle(
                                projectState.config.bundle.copyWith(
                                  skillIds: List<String>.unmodifiable(ids),
                                ),
                              ),
                            );
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
