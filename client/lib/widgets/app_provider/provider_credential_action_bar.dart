import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../app_dialog.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/provider_credential_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/debounce/debounce.dart';

/// Registry-driven login / import actions for official account providers.
class ProviderCredentialActionBar extends StatefulWidget {
  const ProviderCredentialActionBar({
    required this.provider,
    this.ensureSaved,
    super.key,
  });

  final AppProviderConfig provider;

  /// Persists the provider row before credential IO (required on add form).
  final Future<AppProviderConfig?> Function()? ensureSaved;

  @override
  State<ProviderCredentialActionBar> createState() =>
      _ProviderCredentialActionBarState();
}

class _ProviderCredentialActionBarState extends State<ProviderCredentialActionBar> {
  var _running = false;

  ProviderCredentialCapability? _capability(BuildContext context) {
    return CliToolRegistryScope.of(
      context,
    ).capability<ProviderCredentialCapability>(widget.provider.cli);
  }

  @override
  Widget build(BuildContext context) {
    final capability = _capability(context);
    if (capability == null || !capability.appliesTo(widget.provider)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final ready = widget.provider.credentialStatus == 'ready';
    final specs = capability.actionsFor(widget.provider).where((spec) {
      if (ready && !spec.showWhenReady) return false;
      if (!ready && spec.kind == ProviderCredentialActionKind.revoke) {
        return false;
      }
      return true;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _sectionTitle(l10n, widget.provider.cli),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ProviderCredentialStatusBadge(
              cli: widget.provider.cli,
              ready: ready,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spec in specs)
              _actionButton(context, capability: capability, spec: spec),
          ],
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required ProviderCredentialCapability capability,
    required ProviderCredentialActionSpec spec,
  }) {
    final label = _actionLabel(context.l10n, widget.provider.cli, spec.kind);
    final onPressed = _running
        ? null
        : throttledOnPressed(
            'provider_cred_${widget.provider.cli.value}_${spec.kind.name}_${widget.provider.id}',
            () => _runAction(capability, spec.kind),
          );

    if (spec.primary) {
      return FilledButton.tonal(onPressed: onPressed, child: Text(label));
    }
    if (spec.kind == ProviderCredentialActionKind.revoke) {
      return TextButton(onPressed: onPressed, child: Text(label));
    }
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }

  Future<void> _runAction(
    ProviderCredentialCapability capability,
    ProviderCredentialActionKind kind,
  ) async {
    if (_running) return;
    setState(() => _running = true);
    final l10n = context.l10n;
    try {
      var provider = widget.provider;
      final ensureSaved = widget.ensureSaved;
      if (ensureSaved != null) {
        final saved = await ensureSaved();
        if (!mounted) return;
        if (saved == null) {
          AppToast.show(
            context,
            message: l10n.providerName,
            variant: AppToastVariant.error,
          );
          return;
        }
        provider = saved;
      }

      final ready = provider.credentialStatus == 'ready';
      if (kind == ProviderCredentialActionKind.importFile) {
        await _importFile(provider, ready: ready);
        return;
      }
      if (kind == ProviderCredentialActionKind.importDirectory) {
        await _importDirectory(provider, ready: ready);
        return;
      }
      if (kind == ProviderCredentialActionKind.revoke) {
        await _confirmRevoke(provider);
        return;
      }

      final cubit = context.read<AppProviderCubit>();
      final ok = await cubit.runProviderCredentialAction(
        provider: provider,
        kind: kind,
        replace: ready,
        homeDirectory: AppStorage.home,
      );
      if (!mounted) return;
      _showResult(ok);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importFile(AppProviderConfig provider, {required bool ready}) async {
    final l10n = context.l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: _actionLabel(
        l10n,
        provider.cli,
        ProviderCredentialActionKind.importFile,
      ),
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    final cubit = context.read<AppProviderCubit>();
    final ok = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.importFile,
      pickedPath: path,
      replace: ready,
    );
    if (!mounted) return;
    _showResult(ok);
  }

  Future<void> _importDirectory(
    AppProviderConfig provider, {
    required bool ready,
  }) async {
    final l10n = context.l10n;
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: _actionLabel(
        l10n,
        provider.cli,
        ProviderCredentialActionKind.importDirectory,
      ),
    );
    if (directory != null && directory.trim().isNotEmpty) {
      final normalized = p.normalize(directory.trim());
      final path = _resolveCursorImportPath(normalized);
      if (path == null || !mounted) return;
      final cubit = context.read<AppProviderCubit>();
      final ok = await cubit.runProviderCredentialAction(
        provider: provider,
        kind: ProviderCredentialActionKind.importDirectory,
        pickedPath: path,
        replace: ready,
      );
      if (!mounted) return;
      _showResult(ok);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: _actionLabel(
        l10n,
        provider.cli,
        ProviderCredentialActionKind.importDirectory,
      ),
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty || !mounted) return;
    final resolved = _resolveCursorImportPath(p.normalize(path.trim()));
    if (resolved == null) return;
    final cubit = context.read<AppProviderCubit>();
    final ok = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.importDirectory,
      pickedPath: resolved,
      replace: ready,
    );
    if (!mounted) return;
    _showResult(ok);
  }

  String? _resolveCursorImportPath(String normalized) {
    if (widget.provider.cli != CliTool.cursor) return normalized;
    if (_isConfigCursorDir(normalized)) {
      return p.join(normalized, 'auth.json');
    }
    if (p.basename(normalized) == 'auth.json') return normalized;
    if (p.basename(normalized) == 'cli-config.json') {
      return p.dirname(normalized);
    }
    if (p.basename(normalized) == '.cursor') return normalized;
    final nested = p.join(normalized, '.cursor');
    if (p.basename(nested) == '.cursor') return nested;
    return normalized;
  }

  bool _isConfigCursorDir(String normalized) {
    if (p.basename(normalized) != 'cursor') return false;
    return p.basename(p.dirname(normalized)) == '.config';
  }

  Future<void> _confirmRevoke(AppProviderConfig provider) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: _actionLabel(
                l10n,
                provider.cli,
                ProviderCredentialActionKind.revoke,
              ),
            ),
            const SizedBox(height: 16),
            Text(_revokeConfirmMessage(l10n, provider)),
            AppDialogActions(
              children: [
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
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final cubit = context.read<AppProviderCubit>();
    final ok = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.revoke,
    );
    if (!mounted) return;
    _showResult(ok);
  }

  void _showResult(bool ok) {
    final l10n = context.l10n;
    AppToast.show(
      context,
      message: ok
          ? _successMessage(l10n, widget.provider.cli)
          : _failureMessage(l10n, widget.provider.cli),
      variant: ok ? AppToastVariant.success : AppToastVariant.error,
    );
  }
}

class ProviderCredentialStatusBadge extends StatelessWidget {
  const ProviderCredentialStatusBadge({
    required this.cli,
    required this.ready,
    super.key,
  });

  final CliTool cli;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final label = ready
        ? _authenticatedLabel(l10n, cli)
        : _unauthenticatedLabel(l10n, cli);
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

String _sectionTitle(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsTitle,
    CliTool.cursor => l10n.appProviderToolCursor,
    CliTool.codex => l10n.appProviderToolCodex,
    CliTool.opencode => l10n.appProviderToolOpencode,
    _ => l10n.claudeOfficialCredentialsTitle,
  };
}

String _actionLabel(
  AppLocalizations l10n,
  CliTool cli,
  ProviderCredentialActionKind kind,
) {
  return switch (kind) {
    ProviderCredentialActionKind.login => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsLogin,
      CliTool.cursor => l10n.cursorCredentialsLogin,
      CliTool.codex => l10n.codexCredentialsLogin,
      CliTool.opencode => l10n.opencodeCredentialsLogin,
      _ => l10n.claudeOfficialCredentialsLogin,
    },
    ProviderCredentialActionKind.importGlobal => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsImportGlobal,
      CliTool.cursor => l10n.cursorCredentialsImportGlobal,
      CliTool.codex => l10n.codexCredentialsImportGlobal,
      CliTool.opencode => l10n.opencodeCredentialsImportGlobal,
      _ => l10n.appProviderImport,
    },
    ProviderCredentialActionKind.importFile => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsImportFile,
      CliTool.codex => l10n.codexCredentialsImportFile,
      CliTool.opencode => l10n.opencodeCredentialsImportFile,
      _ => l10n.cursorCredentialsImportFile,
    },
    ProviderCredentialActionKind.importDirectory =>
      l10n.cursorCredentialsImportFile,
    ProviderCredentialActionKind.revoke => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsRevoke,
      CliTool.cursor => l10n.cursorCredentialsRevoke,
      CliTool.codex => l10n.codexCredentialsRevoke,
      CliTool.opencode => l10n.opencodeCredentialsRevoke,
      _ => l10n.claudeOfficialCredentialsRevoke,
    },
  };
}

String _authenticatedLabel(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsAuthenticated,
    CliTool.cursor => l10n.cursorCredentialsAuthenticated,
    _ => l10n.claudeOfficialCredentialsAuthenticated,
  };
}

String _unauthenticatedLabel(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsUnauthenticated,
    CliTool.cursor => l10n.cursorCredentialsUnauthenticated,
    _ => l10n.claudeOfficialCredentialsUnauthenticated,
  };
}

String _successMessage(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsActionSuccess,
    CliTool.cursor => l10n.cursorCredentialsActionSuccess,
    CliTool.codex => l10n.codexCredentialsActionSuccess,
    CliTool.opencode => l10n.opencodeCredentialsActionSuccess,
    _ => l10n.claudeOfficialCredentialsActionSuccess,
  };
}

String _failureMessage(AppLocalizations l10n, CliTool cli) {
  return switch (cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsActionFailed,
    CliTool.cursor => l10n.cursorCredentialsActionFailed,
    CliTool.codex => l10n.codexCredentialsActionFailed,
    CliTool.opencode => l10n.opencodeCredentialsActionFailed,
    _ => l10n.claudeOfficialCredentialsActionFailed,
  };
}

String _revokeConfirmMessage(AppLocalizations l10n, AppProviderConfig provider) {
  return switch (provider.cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsRevokeConfirm(
      provider.name,
    ),
    CliTool.cursor => l10n.cursorCredentialsRevokeConfirm(provider.name),
    CliTool.codex => l10n.codexCredentialsRevokeConfirm(provider.name),
    CliTool.opencode => l10n.opencodeCredentialsRevokeConfirm(provider.name),
    _ => l10n.claudeOfficialCredentialsRevokeConfirm(provider.name),
  };
}
