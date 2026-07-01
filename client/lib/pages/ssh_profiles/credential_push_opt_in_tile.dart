import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

/// Per-target "push credentials to this machine" opt-in (P3c §3.4). Default
/// **off**. Turning it on first shows a trust-boundary confirmation naming the
/// remote [host]; only on confirm does [onChanged] fire with `true` (the caller
/// persists `credentialOptIn` in targets.json). Turning it off persists `false`
/// immediately. The confirm step is injected so it is widget-testable.
class CredentialPushOptInTile extends StatelessWidget {
  const CredentialPushOptInTile({
    required this.host,
    required this.optedIn,
    required this.onChanged,
    this.confirmTrustBoundary,
    this.showDividerBelow = true,
    super.key,
  });

  final String host;
  final bool optedIn;
  final ValueChanged<bool> onChanged;
  final bool showDividerBelow;

  /// Returns true when the user confirms pushing keys to [host]. Defaults to
  /// [showCredentialPushConfirm].
  final Future<bool> Function()? confirmTrustBoundary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsLabeledRow(
      title: l10n.credentialPushOptInTitle,
      subtitle: l10n.credentialPushOptInSubtitle,
      trailing: Switch(
        value: optedIn,
        onChanged: (next) {
          if (!next) {
            onChanged(false);
            return;
          }
          final confirm = confirmTrustBoundary ??
              () => showCredentialPushConfirm(context, host);
          confirm().then((ok) {
            if (ok) onChanged(true);
          });
        },
      ),
      showDividerBelow: showDividerBelow,
    );
  }
}

/// Trust-boundary confirmation before the first credential push to [host].
Future<bool> showCredentialPushConfirm(BuildContext context, String host) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.credentialPushConfirmTitle),
          const SizedBox(height: 12),
          Text(l10n.credentialPushConfirmBody(host)),
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
                child: Text(l10n.credentialPushConfirmAction),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
