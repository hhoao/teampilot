import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/provider/claude/claude_official_provider.dart';
import '../../utils/debounce/debounce.dart';

/// Compact auth status chip for Claude Official providers.
class ClaudeOfficialCredentialStatusBadge extends StatelessWidget {
  const ClaudeOfficialCredentialStatusBadge({required this.ready, super.key});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final label = ready
        ? l10n.claudeOfficialCredentialsAuthenticated
        : l10n.claudeOfficialCredentialsUnauthenticated;
    final bg = ready ? cs.primaryContainer : cs.errorContainer;
    final fg = ready ? cs.onPrimaryContainer : cs.onErrorContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class ClaudeOfficialCredentialActions extends StatefulWidget {
  const ClaudeOfficialCredentialActions({required this.provider, super.key});

  final AppProviderConfig provider;

  @override
  State<ClaudeOfficialCredentialActions> createState() =>
      _ClaudeOfficialCredentialActionsState();
}

class _ClaudeOfficialCredentialActionsState
    extends State<ClaudeOfficialCredentialActions> {
  var _running = false;

  AppProviderConfig get provider => widget.provider;

  @override
  Widget build(BuildContext context) {
    if (!isOfficialClaudeProvider(provider)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final cubit = context.read<AppProviderCubit>();
    final ready = provider.hasClaudeCredentialsReady;
    final disabled = _running;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'claude_official_login_${provider.id}',
                  () => _run(
                    () => cubit.loginClaudeOfficialProvider(provider.id),
                  ),
                ),
          child: Text(l10n.claudeOfficialCredentialsLogin),
        ),
        OutlinedButton(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'claude_official_import_global_${provider.id}',
                  () => _run(
                    () => cubit.importClaudeCredentialsFromGlobal(
                      provider.id,
                      replace: ready,
                    ),
                  ),
                ),
          child: Text(l10n.claudeOfficialCredentialsImportGlobal),
        ),
        OutlinedButton(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'claude_official_import_file_${provider.id}',
                  () => _importFromFile(cubit),
                ),
          child: Text(l10n.claudeOfficialCredentialsImportFile),
        ),
        if (ready)
          TextButton(
            onPressed: disabled
                ? null
                : throttledOnPressed(
                    'claude_official_revoke_${provider.id}',
                    () => _confirmRevoke(cubit),
                  ),
            child: Text(l10n.claudeOfficialCredentialsRevoke),
          ),
      ],
    );
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_running) return;
    setState(() => _running = true);
    final l10n = context.l10n;
    try {
      final ok = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.claudeOfficialCredentialsActionSuccess
                : l10n.claudeOfficialCredentialsActionFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importFromFile(AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: l10n.claudeOfficialCredentialsImportFile,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _run(
      () => cubit.importClaudeCredentialsFromFile(
        provider.id,
        path,
        replace: provider.hasClaudeCredentialsReady,
      ),
    );
  }

  Future<void> _confirmRevoke(AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.claudeOfficialCredentialsRevoke),
        content: Text(
          l10n.claudeOfficialCredentialsRevokeConfirm(provider.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => cubit.revokeClaudeOfficialProvider(provider.id));
    }
  }
}
