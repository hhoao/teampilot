import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../repositories/identity_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/storage/identity_provisioner.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../utils/workspace_path_picker.dart';
import '../../utils/workspace_path_utils.dart';
import '../../l10n/l10n_extensions.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

/// Large centered "create workspace" modal launched from the workspace workspaces
/// toolbar. A workspace is one or more working directories plus an optional
/// display name: the first folder is the primary path and the rest become
/// additional directories.
Future<void> showHomeNewWorkspaceDialog(
  BuildContext context, {
  required ChatCubit chatCubit,
  required SessionRepository repository,
  IdentityRepository? identityRepository,
}) async {
  final result = await showDialog<({List<String> directories, String display})>(
    context: context,
    builder: (_) => const HomeNewWorkspaceDialog(),
  );
  if (result == null || !context.mounted || result.directories.isEmpty) return;

  final workspaceId = await chatCubit.createWorkspaceWithFirstSession(
    result.directories.first,
    repository,
    sessionTeamId: '',
    additionalPaths: result.directories.skip(1).toList(growable: false),
    display: result.display,
    identityRepository:
        identityRepository ?? context.read<IdentityRepository>(),
  );
  if (!context.mounted) return;
  context.go(
    '/home-v2/workspace/$workspaceId?as=${IdentityProvisioner.defaultPersonalId}',
  );
}

class HomeNewWorkspaceDialog extends StatefulWidget {
  const HomeNewWorkspaceDialog({super.key});

  @override
  State<HomeNewWorkspaceDialog> createState() =>
      _HomeNewWorkspaceDialogState();
}

class _HomeNewWorkspaceDialogState
    extends State<HomeNewWorkspaceDialog> {
  late final TextEditingController _nameController;
  final List<String> _directories = [];

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

  Future<void> _addDirectory() async {
    final picked = await pickWorkspaceDirectoryPath(context);
    final trimmed = picked?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (workspacePathsContains(_directories, trimmed)) return;
    setState(() => _directories.add(trimmed));
  }

  void _removeDirectory(String path) {
    setState(() => _directories.remove(path));
  }

  void _submit() {
    if (_directories.isEmpty) return;
    Navigator.of(context).pop((
      directories: List<String>.unmodifiable(_directories),
      display: _nameController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final hasDirectory = _directories.isNotEmpty;

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
          _DirectoryPicker(
            directories: _directories,
            onAdd: _addDirectory,
            onRemove: _removeDirectory,
          ),
          const SizedBox(height: 16),
          _NameField(
            controller: _nameController,
            hint: hasDirectory
                ? _basename(_directories.first)
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

class _DirectoryPicker extends StatelessWidget {
  const _DirectoryPicker({
    required this.directories,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> directories;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final hasDirectory = directories.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDirectory
              ? cs.primary.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary,
                      Color.lerp(cs.primary, cs.tertiary, 0.6) ?? cs.primary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  size: context.appIconSizes.lg,
                  color: cs.onPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.homeWorkspaceNewWorkspaceDirectoryLabel,
                  style: styles.bodyStrong.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: Icon(
                  Icons.drive_folder_upload_outlined,
                  size: context.appIconSizes.md,
                ),
                label: Text(l10n.homeWorkspaceNewWorkspaceChooseDirectory),
              ),
            ],
          ),
          if (!hasDirectory) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Text(
                l10n.homeWorkspaceNewWorkspaceDirectoryHint,
                style: styles.body.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ] else
            for (var i = 0; i < directories.length; i++)
              _DirectoryRow(
                path: directories[i],
                isPrimary: i == 0,
                onRemove: () => onRemove(directories[i]),
              ),
        ],
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.path,
    required this.isPrimary,
    required this.onRemove,
  });

  final String path;
  final bool isPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            isPrimary
                ? Icons.star_rounded
                : Icons.subdirectory_arrow_right_rounded,
            size: context.appIconSizes.md,
            color: isPrimary ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.body.copyWith(color: cs.onSurface),
            ),
          ),
          IconButton(
            tooltip: l10n.removeWorkspaceDirectory,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: context.appIconSizes.sm,
              color: cs.onSurfaceVariant,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.workspaceDisplayName,
            style: styles.caption.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onSubmitted: onSubmitted,
            style: styles.prominent.copyWith(color: cs.onSurface),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}
