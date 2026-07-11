import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../models/workspace_topology.dart';
import '../../../services/storage/home_target_controller.dart';
import '../../../utils/team_member_naming.dart';
import '../../../theme/app_text_styles.dart';

/// Practical per-host cap for non-lead replica placement in mixed workspaces.
const memberPlacementMaxPerHost = 99;

bool canIncrementMemberPlacement({
  required TeamMemberConfig member,
  required List<WorkspaceFolder> folders,
  required String selectedTargetId,
  required int countOnMachine,
}) {
  if (TeamMemberNaming.isTeamLead(member)) {
    final preferred = preferredLeadHost(folders);
    if (preferred == null || selectedTargetId != preferred) return false;
    return countOnMachine < 1;
  }
  return countOnMachine < memberPlacementMaxPerHost;
}

bool canDecrementMemberPlacement({
  required TeamMemberConfig member,
  required List<WorkspaceFolder> folders,
  required String selectedTargetId,
  required int countOnMachine,
}) {
  if (countOnMachine <= 0) return false;
  if (TeamMemberNaming.isTeamLead(member)) {
    final preferred = preferredLeadHost(folders);
    if (preferred != null && selectedTargetId == preferred) return false;
  }
  return true;
}

/// Left: workspace machines. Right: roster members with +/- instance counts on
/// the selected machine.
class MixedWorkspaceMemberPlacementPanel extends StatefulWidget {
  const MixedWorkspaceMemberPlacementPanel({
    required this.workspace,
    required this.members,
    required this.placement,
    required this.onPlacementChanged,
    super.key,
  });

  final Workspace workspace;
  final List<TeamMemberConfig> members;
  final MemberPlacementByTarget placement;
  final ValueChanged<MemberPlacementByTarget> onPlacementChanged;

  @override
  State<MixedWorkspaceMemberPlacementPanel> createState() =>
      _MixedWorkspaceMemberPlacementPanelState();
}

class _MixedWorkspaceMemberPlacementPanelState
    extends State<MixedWorkspaceMemberPlacementPanel> {
  late String _selectedTargetId;

  @override
  void initState() {
    super.initState();
    _selectedTargetId = workspaceTargetIds(widget.workspace.folders).first;
  }

  @override
  void didUpdateWidget(covariant MixedWorkspaceMemberPlacementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = workspaceTargetIds(widget.workspace.folders);
    if (!ids.contains(_selectedTargetId)) {
      _selectedTargetId = ids.first;
    }
  }

  void _setCount(String memberTypeId, int nextOnMachine) {
    final next = <String, Map<String, int>>{
      for (final entry in widget.placement.entries)
        entry.key: Map<String, int>.from(entry.value),
    };
    final counts = Map<String, int>.from(
      next.putIfAbsent(_selectedTargetId, () => {}),
    );
    if (nextOnMachine <= 0) {
      counts.remove(memberTypeId);
    } else {
      counts[memberTypeId] = nextOnMachine;
    }
    if (counts.isEmpty) {
      next.remove(_selectedTargetId);
    } else {
      next[_selectedTargetId] = counts;
    }
    widget.onPlacementChanged(next);
  }

  int _instancesOnTarget(String targetId) {
    final counts = widget.placement[targetId];
    if (counts == null) return 0;
    return counts.values.fold<int>(0, (sum, n) => sum + n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<HomeTargetController>();
    final targetIds = workspaceTargetIds(widget.workspace.folders);
    final members = widget.members.where((m) => m.isValid).toList();
    final folders = widget.workspace.folders;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: FutureBuilder<List<RuntimeTarget>>(
            future: controller.listSelectable(),
            builder: (context, snapshot) {
              final labels = {
                for (final t in snapshot.data ?? const <RuntimeTarget>[])
                  t.id: t.label,
              };
              return ListView(
                children: [
                  for (final targetId in targetIds)
                    _TargetTile(
                      selected: targetId == _selectedTargetId,
                      label: labels[targetId] ?? targetId,
                      paths: folderPathsForTarget(
                        widget.workspace.folders,
                        targetId,
                      ),
                      instanceCount: _instancesOnTarget(targetId),
                      onTap: () => setState(() => _selectedTargetId = targetId),
                    ),
                ],
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(left: 8),
            children: [
              for (final member in members)
                Builder(
                  builder: (context) {
                    final placedTotal = memberPlacementCountForType(
                      widget.placement,
                      member.id,
                    );
                    final countOnMachine =
                        widget.placement[_selectedTargetId]?[member.id] ?? 0;
                    return _MemberPlacementRow(
                      memberLabel: member.name.isEmpty
                          ? l10n.memberName
                          : member.name,
                      placedTotal: placedTotal,
                      countOnMachine: countOnMachine,
                      canIncrement: canIncrementMemberPlacement(
                        member: member,
                        folders: folders,
                        selectedTargetId: _selectedTargetId,
                        countOnMachine: countOnMachine,
                      ),
                      canDecrement: canDecrementMemberPlacement(
                        member: member,
                        folders: folders,
                        selectedTargetId: _selectedTargetId,
                        countOnMachine: countOnMachine,
                      ),
                      onIncrement: () {
                        if (!canIncrementMemberPlacement(
                          member: member,
                          folders: folders,
                          selectedTargetId: _selectedTargetId,
                          countOnMachine: countOnMachine,
                        )) {
                          return;
                        }
                        _setCount(member.id, countOnMachine + 1);
                      },
                      onDecrement: () {
                        if (!canDecrementMemberPlacement(
                          member: member,
                          folders: folders,
                          selectedTargetId: _selectedTargetId,
                          countOnMachine: countOnMachine,
                        )) {
                          return;
                        }
                        _setCount(member.id, countOnMachine - 1);
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.selected,
    required this.label,
    required this.paths,
    required this.instanceCount,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final List<String> paths;
  final int instanceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pathPreview = paths.join(', ');
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: ListTile(
        selected: selected,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          pathPreview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.of(context).sm,
        ),
        trailing: instanceCount > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: cs.primary,
                child: Text(
                  '$instanceCount',
                  style: AppTextStyles.of(context).xsColored(cs.onPrimary),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _MemberPlacementRow extends StatelessWidget {
  const _MemberPlacementRow({
    required this.memberLabel,
    required this.placedTotal,
    required this.countOnMachine,
    required this.canIncrement,
    required this.canDecrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String memberLabel;
  final int placedTotal;
  final int countOnMachine;
  final bool canIncrement;
  final bool canDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(memberLabel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mixedWorkspaceMemberPlacementProgress(
                placedTotal,
                placedTotal,
              ),
              style: AppTextStyles.of(context).sm,
            ),
            Text(
              l10n.mixedWorkspaceMemberPlacementOnMachine(countOnMachine),
              style: AppTextStyles.of(context).sm,
            ),
          ],
        ),
        trailing: _PlacementStepper(
          value: countOnMachine,
          canIncrement: canIncrement,
          canDecrement: canDecrement,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
      ),
    );
  }
}

class _PlacementStepper extends StatelessWidget {
  const _PlacementStepper({
    required this.value,
    required this.canIncrement,
    required this.canDecrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int value;
  final bool canIncrement;
  final bool canDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: canDecrement ? onDecrement : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: canIncrement ? onIncrement : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
