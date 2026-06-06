import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../utils/debounce/debounce.dart';

class CursorCredentialActions extends StatefulWidget {
  const CursorCredentialActions({required this.provider, super.key});

  final AppProviderConfig provider;

  @override
  State<CursorCredentialActions> createState() => _CursorCredentialActionsState();
}

class _CursorCredentialActionsState extends State<CursorCredentialActions> {
  var _running = false;

  AppProviderConfig get provider => widget.provider;

  @override
  Widget build(BuildContext context) {
    if (provider.cli != CliTool.cursor) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final cubit = context.read<AppProviderCubit>();
    final ready = provider.hasCursorCredentialsReady;
    final disabled = _running;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'cursor_login_${provider.id}',
                  () => _run(() => cubit.loginCursorProvider(provider.id)),
                ),
          child: Text(l10n.cursorCredentialsLogin),
        ),
        OutlinedButton(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'cursor_import_global_${provider.id}',
                  () => _run(
                    () => cubit.importCursorCredentialsFromGlobal(
                      provider.id,
                      replace: ready,
                    ),
                  ),
                ),
          child: Text(l10n.cursorCredentialsImportGlobal),
        ),
        OutlinedButton(
          onPressed: disabled
              ? null
              : throttledOnPressed(
                  'cursor_import_directory_${provider.id}',
                  () => _importFromDirectory(cubit),
                ),
          child: Text(l10n.cursorCredentialsImportFile),
        ),
        if (ready)
          TextButton(
            onPressed: disabled
                ? null
                : throttledOnPressed(
                    'cursor_revoke_${provider.id}',
                    () => _confirmRevoke(cubit),
                  ),
            child: Text(l10n.cursorCredentialsRevoke),
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
                ? l10n.cursorCredentialsActionSuccess
                : l10n.cursorCredentialsActionFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importFromDirectory(AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.cursorCredentialsImportFile,
    );
    if (directory != null && directory.trim().isNotEmpty) {
      final normalized = p.normalize(directory.trim());
      if (_isConfigCursorDir(normalized)) {
        await _run(
          () => cubit.importCursorAuthJsonFile(
            provider.id,
            p.join(normalized, 'auth.json'),
            replace: provider.hasCursorCredentialsReady,
          ),
        );
        return;
      }
      final cursorDir = _resolveCursorDirectory(directory);
      if (cursorDir == null) return;
      await _run(
        () => cubit.importCursorCredentialsFromDirectory(
          provider.id,
          cursorDir,
          replace: provider.hasCursorCredentialsReady,
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: l10n.cursorCredentialsImportFile,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    if (_isAuthJsonPath(path)) {
      await _run(
        () => cubit.importCursorAuthJsonFile(
          provider.id,
          path,
          replace: provider.hasCursorCredentialsReady,
        ),
      );
      return;
    }
    final cursorDir = _resolveCursorDirectory(path);
    if (cursorDir == null) return;
    await _run(
      () => cubit.importCursorCredentialsFromDirectory(
        provider.id,
        cursorDir,
        replace: provider.hasCursorCredentialsReady,
      ),
    );
  }

  bool _isAuthJsonPath(String path) =>
      p.basename(p.normalize(path.trim())) == 'auth.json';

  String? _resolveCursorDirectory(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final normalized = p.normalize(trimmed);
    if (p.basename(normalized) == 'cli-config.json') {
      return p.dirname(normalized);
    }
    if (p.basename(normalized) == '.cursor') {
      return normalized;
    }
    final nested = p.join(normalized, '.cursor');
    if (p.basename(nested) == '.cursor') {
      return nested;
    }
    return normalized;
  }

  bool _isConfigCursorDir(String normalized) {
    if (p.basename(normalized) != 'cursor') return false;
    return p.basename(p.dirname(normalized)) == '.config';
  }

  Future<void> _confirmRevoke(AppProviderCubit cubit) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cursorCredentialsRevoke),
        content: Text(
          l10n.cursorCredentialsRevokeConfirm(provider.name),
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
      await _run(() => cubit.revokeCursorProvider(provider.id));
    }
  }
}

/// Cursor credential status chip; reuses Claude badge layout with cursor l10n.
class CursorCredentialStatusBadge extends StatelessWidget {
  const CursorCredentialStatusBadge({required this.ready, super.key});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final label = ready
        ? l10n.cursorCredentialsAuthenticated
        : l10n.cursorCredentialsUnauthenticated;
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
