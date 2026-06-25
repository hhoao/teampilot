import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_folder.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/app_dialog.dart';
import 'config/member_folder_assignment_tile.dart';

Future<void> showMemberFolderAssignmentDialog(
  BuildContext context, {
  required SessionRepository repository,
  required String sessionId,
  required String memberId,
  required String memberLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MemberFolderAssignmentDialog(
      repository: repository,
      sessionId: sessionId,
      memberId: memberId,
      memberLabel: memberLabel,
    ),
  );
}

class _MemberFolderAssignmentDialog extends StatefulWidget {
  const _MemberFolderAssignmentDialog({
    required this.repository,
    required this.sessionId,
    required this.memberId,
    required this.memberLabel,
  });

  final SessionRepository repository;
  final String sessionId;
  final String memberId;
  final String memberLabel;

  @override
  State<_MemberFolderAssignmentDialog> createState() =>
      _MemberFolderAssignmentDialogState();
}

class _MemberFolderAssignmentDialogState
    extends State<_MemberFolderAssignmentDialog> {
  bool _loading = true;
  var _currentTargetId = '';
  var _workspaceId = '';
  var _folders = const <WorkspaceFolder>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.repository.loadSessions();
    final workspaces = await widget.repository.loadWorkspaces();
    final session = sessions
        .where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    final workspace = session == null
        ? null
        : workspaces
            .where((w) => w.workspaceId == session.workspaceId)
            .firstOrNull;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _workspaceId = session?.workspaceId ?? '';
      _folders = workspace?.folders ?? session?.folders ?? const [];
      _currentTargetId =
          session?.memberTargets[widget.memberId]?.trim() ?? '';
    });
  }

  Future<void> _assign(String targetId) async {
    await widget.repository.setMemberTarget(
      widget.sessionId,
      widget.memberId,
      targetId,
    );
    if (!mounted) return;
    setState(() => _currentTargetId = targetId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_workspaceId.isEmpty || _folders.isEmpty) {
      body = Center(child: Text(l10n.memberDetailLoadError));
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          MemberFolderAssignmentTile(
            memberLabel: widget.memberLabel,
            workspace: Workspace(
              workspaceId: _workspaceId,
              folders: _folders,
              createdAt: 0,
            ),
            currentTargetId: _currentTargetId,
            requireExplicitTarget: workspaceTopologyRequiresMemberAssignment(
              _folders,
            ),
            onAssign: _assign,
          ),
        ],
      );
    }

    return AppDialog(
      maxWidth: 640,
      maxHeight: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.memberTargetAssignmentTitle),
          Expanded(child: body),
        ],
      ),
    );
  }
}
