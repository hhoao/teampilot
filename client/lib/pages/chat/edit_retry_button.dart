import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Red retry affordance under a user bubble whose edit failed or was stopped.
///
/// The transaction itself stays invisible: the sheet closes on submit, so this
/// is the only place the author can resend the same text without reopening the
/// editor. Desktop keeps its inline editor and therefore never shows it.
class EditRetryButton extends StatelessWidget {
  const EditRetryButton({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: const ValueKey('chat-edit-retry'),
        onPressed: onRetry,
        style: TextButton.styleFrom(
          foregroundColor: scheme.error,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 28),
        ),
        child: Text(
          context.l10n.edit.retry,
          style: TpTextStyles.of(context).smColored(scheme.error),
        ),
      ),
    );
  }
}
