import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../services/storage/home_target_controller.dart';

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
                _MemberPlacementRow(
                  memberLabel: member.name.isEmpty
                      ? l10n.memberName
                      : member.name,
                  needed: memberTypeReplicaCount(member),
                  placedTotal: memberPlacementCountForType(
                    widget.placement,
                    member.id,
                  ),
                  countOnMachine:
                      widget.placement[_selectedTargetId]?[member.id] ?? 0,
                  onIncrement: () {
                    final onMachine =
                        widget.placement[_selectedTargetId]?[member.id] ?? 0;
                    final total = memberPlacementCountForType(
                      widget.placement,
                      member.id,
                    );
                    if (total >= memberTypeReplicaCount(member)) return;
                    _setCount(member.id, onMachine + 1);
                  },
                  onDecrement: () {
                    final onMachine =
                        widget.placement[_selectedTargetId]?[member.id] ?? 0;
                    if (onMachine <= 0) return;
                    _setCount(member.id, onMachine - 1);
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
    return ListTile(
      selected: selected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        pathPreview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: instanceCount > 0
          ? CircleAvatar(
              radius: 12,
              backgroundColor: cs.primary,
              child: Text(
                '$instanceCount',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onPrimary,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _MemberPlacementRow extends StatelessWidget {
  const _MemberPlacementRow({
    required this.memberLabel,
    required this.needed,
    required this.placedTotal,
    required this.countOnMachine,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String memberLabel;
  final int needed;
  final int placedTotal;
  final int countOnMachine;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final complete = placedTotal == needed;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(memberLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.mixedWorkspaceMemberPlacementProgress(placedTotal, needed),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: complete ? cs.onSurfaceVariant : cs.error,
            ),
          ),
          Text(
            l10n.mixedWorkspaceMemberPlacementOnMachine(countOnMachine),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: _PlacementStepper(
        value: countOnMachine,
        canIncrement: placedTotal < needed,
        canDecrement: countOnMachine > 0,
        onIncrement: onIncrement,
        onDecrement: onDecrement,
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
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: canIncrement ? onIncrement : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
