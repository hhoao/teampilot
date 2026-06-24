import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../l10n/l10n_extensions.dart';
import '../models/workspace_folder.dart';
import 'app_dialog.dart';
import 'workspace_create_directory_picker.dart';

typedef CreateWorkspaceDraft = ({
  List<WorkspaceFolder> folders,
  String display,
});

Future<CreateWorkspaceDraft?> showCreateWorkspaceDialog(BuildContext context) {
  return showDialog<CreateWorkspaceDraft>(
    context: context,
    builder: (ctx) => const _CreateWorkspaceDialog(),
  );
}

class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog();

  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  final _displayController = TextEditingController();
  var _targetId = WorkspaceFolder.localTargetId;
  var _folders = <WorkspaceFolder>[];

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  void _onTargetChanged(String next) {
    if (next == _targetId) return;
    setState(() => _targetId = next);
  }

  void _create() {
    final l10n = context.l10n;
    final valid = _folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      AppToast.show(
        context,
        message: l10n.workspacePrimaryPathRequired,
        variant: AppToastVariant.error,
      );
      return;
    }
    Navigator.of(context).pop((
      folders: valid,
      display: _displayController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasDirectory = _folders.isNotEmpty;
    final firstPath = hasDirectory ? _folders.first.path : '';

    return AppDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.newWorkspace),
          const SizedBox(height: 16),
          WorkspaceCreateDirectoryPicker(
            targetId: _targetId,
            onTargetChanged: _onTargetChanged,
            folders: _folders,
            onFoldersChanged: (next) => setState(() => _folders = next),
          ),
          const SizedBox(height: 16),
          WorkspaceCreateNameField(
            controller: _displayController,
            hint: hasDirectory
                ? _basename(firstPath)
                : l10n.homeWorkspaceNewWorkspaceNameHint,
            onSubmitted: (_) => _create(),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: hasDirectory ? _create : null,
                child: Text(l10n.create),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _basename(String path) {
    final parts = path.replaceAll(r'\', '/').split('/')
      ..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }
}
