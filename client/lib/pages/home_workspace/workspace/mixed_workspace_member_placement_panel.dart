import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../repositories/ssh_profile_repository.dart';
import '../../../services/remote/remote_cli_readiness.dart';
import '../../../services/storage/home_target_controller.dart';
import '../../../services/workspace/target_liveness.dart';
import '../../../utils/team/team_member_naming.dart';
import '../../../widgets/workspace/workspace_dead_target_remap_dialog.dart';
import 'remote_cli_machine_readiness_panel.dart';

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
    this.onWorkspaceRemapped,
    this.team,
    this.globalPresets = const [],
    this.remoteCliReadiness,
    super.key,
  });

  final Workspace workspace;
  final List<TeamMemberConfig> members;
  final MemberPlacementByTarget placement;
  final ValueChanged<MemberPlacementByTarget> onPlacementChanged;
  final ValueChanged<Workspace>? onWorkspaceRemapped;
  final TeamProfile? team;
  final List<CliPreset> globalPresets;
  final RemoteCliReadinessService? remoteCliReadiness;

  @override
  State<MixedWorkspaceMemberPlacementPanel> createState() =>
      _MixedWorkspaceMemberPlacementPanelState();
}

class _MixedWorkspaceMemberPlacementPanelState
    extends State<MixedWorkspaceMemberPlacementPanel> {
  late String _selectedTargetId;
  List<RuntimeTarget> _selectableTargets = const [];
  Future<void>? _targetsLoad;
  var _remapping = false;
  Set<String> _deadTargetIds = const {};
  List<String>? _deadCheckKey;

  TargetLiveness _liveness(BuildContext context) =>
      DefaultTargetLiveness(sshProfiles: context.read<SshProfileRepository>());

  void _ensureDeadTargetsChecked(List<String> targetIds) {
    if (_deadCheckKey != null && listEquals(_deadCheckKey, targetIds)) return;
    _deadCheckKey = List<String>.from(targetIds);
    _loadDeadTargets(targetIds);
  }

  Future<void> _loadDeadTargets(List<String> targetIds) async {
    final TargetLiveness liveness;
    try {
      liveness = _liveness(context);
    } on Object {
      // SshProfileRepository unavailable in lightweight widget tests.
      return;
    }
    final dead = <String>{};
    for (final id in targetIds) {
      if (!await liveness.isAlive(id)) {
        dead.add(id);
      }
    }
    if (!mounted) return;
    if (_deadCheckKey != null && listEquals(_deadCheckKey, targetIds)) {
      setState(() => _deadTargetIds = dead);
    }
  }

  void _invalidateDeadTargetCache() {
    _deadCheckKey = null;
    _deadTargetIds = const {};
  }

  @override
  void initState() {
    super.initState();
    _selectedTargetId = workspaceTargetIds(widget.workspace.folders).first;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _targetsLoad ??= _loadSelectableTargets();
  }

  Future<void> _loadSelectableTargets() async {
    try {
      final targets = await context
          .read<HomeTargetController>()
          .listSelectable();
      if (!mounted) return;
      setState(() => _selectableTargets = targets);
    } on Object {
      // HomeTargetController unavailable in widget tests.
    }
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

  Future<void> _remapDeadTarget(String fromTargetId) async {
    if (_remapping) return;
    setState(() => _remapping = true);
    final liveness = _liveness(context);
    final homeTarget = context.read<HomeTargetController>();
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    try {
      final selectable = await homeTarget.listSelectable();
      if (!mounted) return;
      final to = await showWorkspaceDeadTargetRemapDialog(
        context: context,
        fromTargetId: fromTargetId,
        deadTargetIds: _deadTargetIds.toList(),
        selectable: selectable,
        liveness: liveness,
      );
      if (to == null || !mounted) return;

      final updated = await repo.remapWorkspaceTarget(
        widget.workspace.workspaceId,
        fromTargetId: fromTargetId,
        toTargetId: to,
        liveness: liveness,
      );
      chat.invalidateWorkspaceProvision(updated);
      await chat.loadWorkspaceData(repo);
      _invalidateDeadTargetCache();
      widget.onWorkspaceRemapped?.call(updated);
      if (!mounted) return;
      final ids = workspaceTargetIds(updated.folders);
      setState(() {
        if (!ids.contains(_selectedTargetId)) {
          _selectedTargetId = ids.first;
        }
      });
    } on Object {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.workspaceDeadTargetRemapFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _remapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<HomeTargetController>();
    final targetIds = workspaceTargetIds(widget.workspace.folders);
    final members = widget.members.where((m) => m.isValid).toList();
    final folders = widget.workspace.folders;

    _ensureDeadTargetsChecked(targetIds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
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
                            isDead: _deadTargetIds.contains(targetId),
                            remapping: _remapping,
                            onRemap: _deadTargetIds.contains(targetId)
                                ? () => _remapDeadTarget(targetId)
                                : null,
                            onTap: () =>
                                setState(() => _selectedTargetId = targetId),
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
                              widget.placement[_selectedTargetId]?[member.id] ??
                              0;
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
          ),
        ),
        if (widget.team != null && widget.remoteCliReadiness != null)
          RemoteCliMachineReadinessPanel(
            workspace: widget.workspace,
            team: widget.team!,
            placement: widget.placement,
            selectedTargetId: _selectedTargetId,
            globalPresets: widget.globalPresets,
            selectableTargets: _selectableTargets,
            readiness: widget.remoteCliReadiness!,
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
    required this.isDead,
    required this.remapping,
    required this.onRemap,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final List<String> paths;
  final int instanceCount;
  final bool isDead;
  final bool remapping;
  final VoidCallback? onRemap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final pathPreview = paths.join(', ');
    return TpHover(
      backgroundColor: selected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      // The prior Material had no shape (rectangular fill); keep the
      // full-width selection highlight a rectangle, not rounded.
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mdSemiboldColored(cs.onSurface),
                  ),
                ),
                if (instanceCount > 0)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: cs.primary,
                    child: Text(
                      '$instanceCount',
                      style: styles.xsColored(cs.onPrimary),
                    ),
                  ),
              ],
            ),
            if (pathPreview.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                pathPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.sm,
              ),
            ],
            if (isDead) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.workspaceDeadTargetBadge,
                      style: styles.xsColored(cs.onErrorContainer),
                    ),
                  ),
                  if (onRemap != null)
                    TextButton(
                      onPressed: remapping ? null : onRemap,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.workspaceDeadTargetRemap),
                    ),
                ],
              ),
            ],
          ],
        ),
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
              style: TpTextStyles.of(context).sm,
            ),
            Text(
              l10n.mixedWorkspaceMemberPlacementOnMachine(countOnMachine),
              style: TpTextStyles.of(context).sm,
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
