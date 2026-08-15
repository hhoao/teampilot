import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../cubits/hook_cubit.dart';
import '../../../../cubits/workspace_project_config_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_hooks_section.dart';

class WorkspaceHooksSection extends StatelessWidget {
  const WorkspaceHooksSection({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectState = context.watch<WorkspaceProjectConfigCubit>().state;
    if (projectState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final hookState = context.watch<HookCubit>().state;
    final definitions = hookState.definitions;
    final hookIds = projectState.config.bundle.hookIds;
    final assignedCount = definitions.where((d) => hookIds.contains(d.id)).length;
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
                  title: l10n.workspaceHooksAssignedCount(
                    assignedCount,
                    definitions.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/hooks'),
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text(l10n.workspaceHooksManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (definitions.isEmpty)
                  TpEmptyState(
                    icon: Icons.bolt_outlined,
                    title: l10n.hooksNoInstalled,
                    hint: l10n.hooksNoInstalledHint,
                    actionLabel: l10n.workspaceHooksManage,
                    onAction: () => context.go('/hooks'),
                  )
                else
                  for (final definition in definitions)
                    TeamHookRow(
                      definition: definition,
                      assigned: hookIds.contains(definition.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(hookIds);
                        if (assigned) {
                          if (!ids.contains(definition.id)) ids.add(definition.id);
                        } else {
                          ids.remove(definition.id);
                        }
                        unawaited(
                          projectCubit.updateBundle(
                            projectState.config.bundle.copyWith(
                              hookIds: List<String>.unmodifiable(ids),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
