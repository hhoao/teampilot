import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/hook_definition.dart';
import '../../theme/workspace_surface_layers.dart';
import 'team_config_cards.dart';

/// 团队身份的 hooks 启用 section（装配页负责传团队当前 hookIds 与回调）。
class TeamHooksSection extends StatelessWidget {
  const TeamHooksSection({
    required this.assignedIds,
    required this.onAssignedChanged,
    this.onManageGlobal,
    super.key,
  });

  final List<String> assignedIds;
  final void Function(List<String> ids) onAssignedChanged;
  final VoidCallback? onManageGlobal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onManage = onManageGlobal ?? () => context.go('/hooks');
    final hookState = context.watch<HookCubit>().state;
    final definitions = hookState.definitions;
    final assignedCount =
        definitions.where((d) => assignedIds.contains(d.id)).length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(
                  title: l10n.teamHooksAssignedCount(
                    assignedCount,
                    definitions.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.bolt_outlined),
                    label: Text(l10n.teamHooksManage),
                  ),
                ),
                const SizedBox(height: 14),
                if (definitions.isEmpty)
                  TpEmptyState(
                    icon: Icons.bolt_outlined,
                    title: l10n.hooksNoInstalled,
                    hint: l10n.hooksNoInstalledHint,
                    actionLabel: l10n.teamHooksManage,
                    onAction: onManage,
                  )
                else
                  for (final definition in definitions)
                    TeamHookRow(
                      definition: definition,
                      assigned: assignedIds.contains(definition.id),
                      onAssignedChanged: (assigned) {
                        final ids = List<String>.from(assignedIds);
                        if (assigned) {
                          if (!ids.contains(definition.id)) {
                            ids.add(definition.id);
                          }
                        } else {
                          ids.remove(definition.id);
                        }
                        onAssignedChanged(ids);
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

class TeamHookRow extends StatelessWidget {
  const TeamHookRow({
    super.key,
    required this.definition,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final HookDefinition definition;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  Text(
                    definition.name.isEmpty ? definition.id : definition.name,
                    style: TpTextStyles.of(context).mdBold,
                  ),
                  Text(
                    definition.matcher == null
                        ? definition.event.name
                        : '${definition.event.name} · ${definition.matcher}',
                    style: TpTextStyles.of(
                      context,
                    ).smColored(cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}
