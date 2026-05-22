import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/claude_official_provider.dart';

class ClaudeOfficialCredentialActions extends StatelessWidget {
  const ClaudeOfficialCredentialActions({
    required this.provider,
    super.key,
  });

  final AppProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    if (!isOfficialClaudeProvider(provider)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final cubit = context.read<AppProviderCubit>();
    final ready = provider.hasClaudeCredentialsReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.claudeOfficialCredentialsTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          ready ? l10n.claudeOfficialCredentialsReady : l10n.claudeOfficialCredentialsMissing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ready
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: () => _run(context, () => cubit.loginClaudeOfficialProvider(provider.id)),
              child: Text(l10n.claudeOfficialCredentialsLogin),
            ),
            OutlinedButton(
              onPressed: () => _run(
                context,
                () => cubit.importClaudeCredentialsFromGlobal(provider.id, replace: ready),
              ),
              child: Text(l10n.claudeOfficialCredentialsImportGlobal),
            ),
            OutlinedButton(
              onPressed: () => _importFromFile(context, cubit),
              child: Text(l10n.claudeOfficialCredentialsImportFile),
            ),
            if (ready)
              TextButton(
                onPressed: () => _confirmRevoke(context, cubit),
                child: Text(l10n.claudeOfficialCredentialsRevoke),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, Future<bool> Function() action) async {
    final l10n = context.l10n;
    final ok = await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.claudeOfficialCredentialsActionSuccess : l10n.claudeOfficialCredentialsActionFailed,
        ),
      ),
    );
  }

  Future<void> _importFromFile(BuildContext context, AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: l10n.claudeOfficialCredentialsImportFile,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty || !context.mounted) return;
    await _run(
      context,
      () => cubit.importClaudeCredentialsFromFile(
        provider.id,
        path,
        replace: provider.hasClaudeCredentialsReady,
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.claudeOfficialCredentialsRevoke),
        content: Text(l10n.claudeOfficialCredentialsRevokeConfirm(provider.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => cubit.revokeClaudeOfficialProvider(provider.id));
    }
  }
}
