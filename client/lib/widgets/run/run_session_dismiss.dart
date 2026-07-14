import 'package:flutter/material.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/run_session.dart';
import '../app_dialog.dart';

/// Confirms stop when needed, then dismisses [session] from [RunCubit].
///
/// Returns whether the session was dismissed.
Future<bool> dismissRunSessionWithConfirm({
  required BuildContext context,
  required RunCubit cubit,
  required RunSession session,
  void Function(String sessionId)? onCleared,
}) async {
  final running =
      session.status == RunSessionStatus.running ||
      session.status == RunSessionStatus.starting;
  if (running) {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.runStopSessionTitle,
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(height: 12),
            Text(l10n.runStopSessionMessage(session.owned.configuration.name)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.runStopAndClose),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return false;
  }

  await cubit.dismissSession(session.id);
  onCleared?.call(session.id);
  return true;
}
