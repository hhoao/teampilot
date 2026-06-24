import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/workspace_create_directory_picker.dart';
import '../../l10n/l10n_extensions.dart';

/// Large centered "create workspace" modal launched from the workspace workspaces
/// toolbar.
Future<void> showHomeNewWorkspaceDialog(
  BuildContext context, {
  required ChatCubit chatCubit,
  required SessionRepository repository,
  LaunchProfileRepository? identityRepository,
}) async {
  final result = await showDialog<({List<WorkspaceFolder> folders, String display})>(
    context: context,
    builder: (_) => const HomeNewWorkspaceDialog(),
  );
  if (result == null || !context.mounted || result.folders.isEmpty) return;

  final workspaceId = await chatCubit.createWorkspaceWithFirstSession(
    result.folders,
    repository,
    sessionTeamId: '',
    display: result.display,
    allowDuplicate: true,
    identityRepository:
        identityRepository ?? context.read<LaunchProfileRepository>(),
  );
  if (!context.mounted) return;
  context.go(
    '/home-v2/workspace/$workspaceId?as=${LaunchProfileProvisioner.defaultPersonalId}',
  );
}

class HomeNewWorkspaceDialog extends StatefulWidget {
  const HomeNewWorkspaceDialog({super.key});

  @override
  State<HomeNewWorkspaceDialog> createState() => _HomeNewWorkspaceDialogState();
}

class _HomeNewWorkspaceDialogState extends State<HomeNewWorkspaceDialog> {
  late final TextEditingController _nameController;
  var _targetId = WorkspaceFolder.localTargetId;
  var _folders = <WorkspaceFolder>[];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _basename(String path) {
    final parts = path.replaceAll(r'\', '/').split('/')
      ..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  void _onTargetChanged(String next) {
    if (next == _targetId) return;
    setState(() => _targetId = next);
  }

  void _submit() {
    final valid = _folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    Navigator.of(context).pop((
      folders: List<WorkspaceFolder>.unmodifiable(valid),
      display: _nameController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final hasDirectory = _folders.isNotEmpty;
    final firstPath = hasDirectory ? _folders.first.path : '';

    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.newWorkspace),
          const SizedBox(height: 8),
          Text(
            l10n.homeWorkspaceNewWorkspaceSubtitle,
            textAlign: TextAlign.center,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          WorkspaceCreateDirectoryPicker(
            targetId: _targetId,
            onTargetChanged: _onTargetChanged,
            folders: _folders,
            onFoldersChanged: (next) => setState(() => _folders = next),
          ),
          const SizedBox(height: 16),
          WorkspaceCreateNameField(
            controller: _nameController,
            hint: hasDirectory
                ? _basename(firstPath)
                : l10n.homeWorkspaceNewWorkspaceNameHint,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: hasDirectory ? _submit : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                child: Text(l10n.homeWorkspaceCreateWorkspace),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
