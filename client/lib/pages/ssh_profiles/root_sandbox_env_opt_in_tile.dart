import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_dialog.dart';

/// Per-target opt-in to inject `IS_SANDBOX=1` when launching Claude as root
/// outside a detected container. Default **off**; enabling keeps
/// `--dangerously-skip-permissions` instead of dropping it at launch.
class RootSandboxEnvOptInTile extends StatelessWidget {
  const RootSandboxEnvOptInTile({
    required this.host,
    required this.optedIn,
    required this.onChanged,
    this.confirmTrustBoundary,
    super.key,
  });

  final String host;
  final bool optedIn;
  final ValueChanged<bool> onChanged;

  /// Returns true when the user confirms root sandbox env on [host].
  final Future<bool> Function()? confirmTrustBoundary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: optedIn,
      title: Text(l10n.rootSandboxEnvOptInTitle),
      subtitle: Text(l10n.rootSandboxEnvOptInSubtitle(host)),
      onChanged: (next) async {
        if (!next) {
          onChanged(false);
          return;
        }
        final confirm = confirmTrustBoundary ??
            () => showRootSandboxEnvConfirm(context, host);
        if (await confirm()) onChanged(true);
      },
    );
  }
}

Future<bool> showRootSandboxEnvConfirm(BuildContext context, String host) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.rootSandboxEnvConfirmTitle),
          const SizedBox(height: 12),
          Text(l10n.rootSandboxEnvConfirmBody(host)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.rootSandboxEnvConfirmAction),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
