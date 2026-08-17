import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import '../app_toast/app_toast.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/credential_action_result.dart';
import '../../services/cli/registry/capabilities/provider_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/debounce/debounce.dart';
import 'provider_credential_messages.dart';
import 'provider_credential_device_code_dialog.dart';

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

class _ProviderCredentialActionBarState
    extends State<ProviderCredentialActionBar> {
  var _running = false;
  var _deviceDialogOpen = false;

  ProviderCapability? _capability(BuildContext context) {
    return CliToolRegistryScope.of(
      context,
    ).capability<ProviderCapability>(widget.provider.cli);
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
        return widget.provider.credentialUpdatedAt > 0;
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
                style: TpTextStyles.of(context).mdSemiboldTightSnug,
              ),
            ),
            ProviderCredentialStatusBadge(
              cli: widget.provider.cli,
              ready: ready,
            ),
          ],
        ),
        const SizedBox(height: 8),
        BlocListener<AppProviderCubit, AppProviderState>(
          listenWhen: (previous, current) =>
              previous.credentialLoginProviderId !=
                  current.credentialLoginProviderId ||
              previous.credentialLoginDeviceCode !=
                  current.credentialLoginDeviceCode,
          listener: _onCredentialLoginState,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final spec in specs)
                _actionButton(context, capability: capability, spec: spec),
            ],
          ),
        ),
      ],
    );
  }

  bool _isWaitingForDeviceCode(AppProviderState state) {
    return state.credentialLoginProviderId == widget.provider.id &&
        (state.credentialLoginDeviceCode ?? '').isNotEmpty;
  }

  void _onCredentialLoginState(BuildContext context, AppProviderState state) {
    final waiting = _isWaitingForDeviceCode(state);
    if (waiting && !_deviceDialogOpen) {
      _deviceDialogOpen = true;
      unawaited(_openDeviceCodeDialog(context));
      return;
    }
    if (!waiting && _deviceDialogOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openDeviceCodeDialog(BuildContext context) async {
    final cubit = context.read<AppProviderCubit>();
    await ProviderCredentialDeviceCodeDialog.show(context, cubit: cubit);
    if (mounted) _deviceDialogOpen = false;
  }

  Widget _actionButton(
    BuildContext context, {
    required ProviderCapability capability,
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
      return FilledButton.tonal(
        onPressed: onPressed,
        child: _running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      );
    }
    if (spec.kind == ProviderCredentialActionKind.revoke) {
      return TextButton(
        onPressed: onPressed,
        child: _running ? const SizedBox.shrink() : Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      child: _running
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  Future<void> _runAction(
    ProviderCapability capability,
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
            variant: TpToastVariant.error,
          );
          return;
        }
        provider = saved;
      }

      if (kind == ProviderCredentialActionKind.importFile) {
        await _importFile(provider);
        return;
      }
      if (kind == ProviderCredentialActionKind.importDirectory) {
        await _importDirectory(provider);
        return;
      }
      if (kind == ProviderCredentialActionKind.revoke) {
        await _confirmRevoke(provider);
        return;
      }

      final cubit = context.read<AppProviderCubit>();
      final actionResult = await cubit.runProviderCredentialAction(
        provider: provider,
        kind: kind,
        replace: _replaceExistingCredentials(kind),
        homeDirectory: AppStorage.home,
      );
      if (!mounted) return;
      _showResult(actionResult);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _importFile(AppProviderConfig provider) async {
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
    final actionResult = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.importFile,
      pickedPath: path,
      replace: true,
    );
    if (!mounted) return;
    _showResult(actionResult);
  }

  Future<void> _importDirectory(AppProviderConfig provider) async {
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
      final actionResult = await cubit.runProviderCredentialAction(
        provider: provider,
        kind: ProviderCredentialActionKind.importDirectory,
        pickedPath: path,
        replace: true,
      );
      if (!mounted) return;
      _showResult(actionResult);
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
    final actionResult = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.importDirectory,
      pickedPath: resolved,
      replace: true,
    );
    if (!mounted) return;
    _showResult(actionResult);
  }

  String? _resolveCursorImportPath(String normalized) {
    if (widget.provider.cli != CliTool.cursor) return normalized;
    if (_isConfigCursorDir(normalized) || _isWindowsCursorAuthDir(normalized)) {
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

  bool _isWindowsCursorAuthDir(String normalized) {
    if (p.basename(normalized) != 'Cursor') return false;
    return p.basename(p.dirname(normalized)) == 'Roaming';
  }

  Future<void> _confirmRevoke(AppProviderConfig provider) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: _actionLabel(
                l10n,
                provider.cli,
                ProviderCredentialActionKind.revoke,
              ),
            ),
            const SizedBox(height: 16),
            Text(_revokeConfirmMessage(l10n, provider)),
            TpDialogActions(
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
    final actionResult = await cubit.runProviderCredentialAction(
      provider: provider,
      kind: ProviderCredentialActionKind.revoke,
    );
    if (!mounted) return;
    _showResult(actionResult);
  }

  void _showResult(CredentialActionResult result) {
    final l10n = context.l10n;
    AppToast.show(
      context,
      message: result.ok
          ? providerCredentialSuccessMessage(l10n, widget.provider.cli)
          : providerCredentialFailureMessage(l10n, widget.provider.cli, result),
      variant: result.ok ? TpToastVariant.success : TpToastVariant.error,
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
        ? _authenticatedLabel(l10n)
        : _unauthenticatedLabel(l10n);
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
          style: TpTextStyles.of(context).xsSemiboldSnugColored(fg),
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
    CliTool.flashskyai => l10n.appProviderToolFlashskyai,
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
      CliTool.flashskyai => l10n.appProviderToolFlashskyai,
    },
    ProviderCredentialActionKind.importGlobal => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsImportGlobal,
      CliTool.cursor => l10n.cursorCredentialsImportGlobal,
      CliTool.codex => l10n.codexCredentialsImportGlobal,
      CliTool.opencode => l10n.opencodeCredentialsImportGlobal,
      CliTool.flashskyai => l10n.appProviderToolFlashskyai,
    },
    ProviderCredentialActionKind.importFile => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsImportFile,
      CliTool.cursor => l10n.cursorCredentialsImportFile,
      CliTool.codex => l10n.codexCredentialsImportFile,
      CliTool.opencode => l10n.opencodeCredentialsImportFile,
      CliTool.flashskyai => l10n.appProviderToolFlashskyai,
    },
    ProviderCredentialActionKind.importDirectory =>
      l10n.cursorCredentialsImportFile,
    ProviderCredentialActionKind.revoke => switch (cli) {
      CliTool.claude => l10n.claudeOfficialCredentialsRevoke,
      CliTool.cursor => l10n.cursorCredentialsRevoke,
      CliTool.codex => l10n.codexCredentialsRevoke,
      CliTool.opencode => l10n.opencodeCredentialsRevoke,
      CliTool.flashskyai => l10n.appProviderToolFlashskyai,
    },
  };
}

String _authenticatedLabel(AppLocalizations l10n) {
  return l10n.providerCredentialsAuthenticated;
}

String _unauthenticatedLabel(AppLocalizations l10n) {
  return l10n.providerCredentialsUnauthenticated;
}

String _revokeConfirmMessage(
  AppLocalizations l10n,
  AppProviderConfig provider,
) {
  return switch (provider.cli) {
    CliTool.claude => l10n.claudeOfficialCredentialsRevokeConfirm(
      provider.name,
    ),
    CliTool.cursor => l10n.cursorCredentialsRevokeConfirm(provider.name),
    CliTool.codex => l10n.codexCredentialsRevokeConfirm(provider.name),
    CliTool.opencode => l10n.opencodeCredentialsRevokeConfirm(provider.name),
    CliTool.flashskyai => l10n.appProviderToolFlashskyai,
  };
}

bool _replaceExistingCredentials(ProviderCredentialActionKind kind) {
  return switch (kind) {
    ProviderCredentialActionKind.importGlobal ||
    ProviderCredentialActionKind.importFile ||
    ProviderCredentialActionKind.importDirectory => true,
    _ => false,
  };
}
