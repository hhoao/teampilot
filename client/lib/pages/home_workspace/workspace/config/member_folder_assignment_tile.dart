import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/workspace.dart';
import '../../../../services/storage/home_target_controller.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';

/// Assigns one team member to a runtime target (machine).
class MemberFolderAssignmentTile extends StatelessWidget {
  const MemberFolderAssignmentTile({
    required this.memberLabel,
    required this.workspace,
    required this.currentTargetId,
    required this.onAssign,
    this.requireExplicitTarget = false,
    super.key,
  });

  final String memberLabel;
  final Workspace workspace;

  /// Empty = inherit workspace folders.
  final String currentTargetId;
  final bool requireExplicitTarget;

  /// Emits the chosen target id (empty = inherit).
  final ValueChanged<String> onAssign;

  List<String> get _workspaceTargetIds {
    final seen = <String>[];
    for (final f in workspace.folders) {
      if (!seen.contains(f.targetId)) seen.add(f.targetId);
    }
    return seen;
  }

  List<String> _pathsForTarget(String targetId) => [
    for (final f in workspace.folders)
      if (f.targetId == targetId) f.path,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<HomeTargetController>();
    return SettingsLabeledStackedRow(
      title: l10n.memberTargetAssignmentTitle,
      subtitle: l10n.memberTargetAssignmentSubtitle(memberLabel),
      showDividerBelow: true,
      body: FutureBuilder<List<RuntimeTarget>>(
        future: controller.listSelectable(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <RuntimeTarget>[];
          final labelOf = {for (final t in all) t.id: t.label};
          final targetIds = _workspaceTargetIds;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!requireExplicitTarget)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: '',
                  groupValue: currentTargetId,
                  title: Text(l10n.memberTargetAssignmentInherit),
                  onChanged: (_) => onAssign(''),
                ),
              for (final id in targetIds)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: id,
                  groupValue: currentTargetId,
                  title: Text(labelOf[id] ?? id),
                  subtitle: Text(_pathsForTarget(id).join(', ')),
                  onChanged: (_) => onAssign(id),
                ),
            ],
          );
        },
      ),
    );
  }
}
