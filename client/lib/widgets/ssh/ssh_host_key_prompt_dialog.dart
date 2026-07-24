import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../router/app_router.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../utils/logging/logger.dart';

/// Shows a TOFU / mismatch host-key confirmation via the root navigator.
///
/// Always marshals onto the next Flutter frame so SSH handshake callbacks
/// (which may run outside a frame / while another modal is open) can still
/// present UI. Returns `false` when the navigator is unavailable or the user
/// declines.
Future<bool> showSshHostKeyPrompt(HostKeyPromptInfo info) {
  final completer = Completer<bool>();
  appLogger.i(
    '[ssh] host-key prompt requested host=${info.profile.hostIdentifier} '
    'keyType=${info.keyType} mismatch=${info.isMismatch}',
  );

  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) {
    unawaited(_presentHostKeyPrompt(info, completer));
  });
  // Handshake callbacks often fire while the scheduler is idle; without this
  // the post-frame callback may not run until the next user-driven frame.
  binding.scheduleFrame();

  return completer.future;
}

Future<void> _presentHostKeyPrompt(
  HostKeyPromptInfo info,
  Completer<bool> completer,
) async {
  if (completer.isCompleted) return;

  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null || !context.mounted) {
    appLogger.w(
      '[ssh] host-key prompt aborted: navigator context unavailable',
    );
    completer.complete(false);
    return;
  }

  try {
    final accepted = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => _SshHostKeyPromptDialog(info: info),
    );
    appLogger.i(
      '[ssh] host-key prompt closed host=${info.profile.hostIdentifier} '
      'accepted=${accepted == true}',
    );
    if (!completer.isCompleted) completer.complete(accepted == true);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      '[ssh] host-key prompt failed to show '
      'host=${info.profile.hostIdentifier}',
      error: error,
      stackTrace: stackTrace,
    );
    if (!completer.isCompleted) completer.complete(false);
  }
}

class _SshHostKeyPromptDialog extends StatelessWidget {
  const _SshHostKeyPromptDialog({required this.info});

  final HostKeyPromptInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = info.profile.hostIdentifier;
    final title = info.isMismatch
        ? l10n.sshHostKeyMismatchTitle
        : l10n.sshHostKeyUnknownTitle;
    final body = info.isMismatch
        ? l10n.sshHostKeyMismatchBody(host)
        : l10n.sshHostKeyUnknownBody(host);

    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: title,
            onClose: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 12),
          Text(body),
          const SizedBox(height: 16),
          _FingerprintRow(
            label: l10n.sshHostKeyFingerprintLabel,
            value: info.fingerprintHex,
          ),
          if (info.isMismatch &&
              info.previousFingerprintHex != null &&
              info.previousFingerprintHex!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FingerprintRow(
              label: l10n.sshHostKeyPreviousFingerprintLabel,
              value: info.previousFingerprintHex!,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.sshHostKeyKeyTypeLabel(info.keyType),
            style: TpTextStyles.of(context).sm,
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  info.isMismatch
                      ? l10n.sshHostKeyReplaceTrust
                      : l10n.sshHostKeyTrust,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FingerprintRow extends StatelessWidget {
  const _FingerprintRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TpTextStyles.of(context).smMedium),
        const SizedBox(height: 6),
        Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: TpTextStyles.of(context).mono,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.copy,
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: value)),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
