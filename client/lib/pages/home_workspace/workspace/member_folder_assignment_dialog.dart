import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/app_dialog.dart';
import 'config/member_folder_assignment_tile.dart';

/// Opens the per-member folder-assignment dialog from the chat workbench member
/// panel (P3a). Loads the active session's folders + current assignment, renders
/// [MemberFolderAssignmentTile], and persists selections via
/// [SessionRepository.setMemberFolderAssignment].
///
/// [repository] and the `HomeTargetController` (read by the tile) come from the
/// caller's widget tree; the dialog is opened with the root context which sits
/// under those providers.
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
  Workspace? _workspace;
  List<String> _current = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.repository.loadSessions();
    final session = sessions
        .where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _workspace = session == null
          ? null
          : Workspace(
              workspaceId: session.workspaceId,
              folders: session.folders,
              createdAt: 0,
            );
      _current = session?.folderAssignments[widget.memberId] ?? const [];
    });
  }

  Future<void> _assign(List<String> paths) async {
    await widget.repository.setMemberFolderAssignment(
      widget.sessionId,
      widget.memberId,
      paths,
    );
    if (!mounted) return;
    setState(() => _current = paths);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workspace = _workspace;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (workspace == null) {
      body = Center(child: Text(l10n.memberDetailLoadError));
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          MemberFolderAssignmentTile(
            memberLabel: widget.memberLabel,
            workspace: workspace,
            currentAssignment: _current,
            requireExplicitTarget: workspaceTopologyRequiresMemberAssignment(
              workspace.folders,
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
