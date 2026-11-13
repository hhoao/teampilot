import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// Red retry icon at the left of a user bubble whose edit failed or was
/// stopped.
///
/// The thread places it as the leading child of the bubble's row, so it sits on
/// the same line and reads as an action on that message. The transaction itself
/// stays invisible: the sheet closes on submit, so this is the only way to
/// resend the same text without reopening the editor. Desktop keeps its inline
/// editor and therefore never shows it.
class EditRetryButton extends StatelessWidget {
  const EditRetryButton({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        key: const ValueKey('chat-edit-retry'),
        onPressed: onRetry,
        tooltip: context.l10n.edit.retry,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(Icons.refresh_rounded, color: scheme.error),
      ),
    );
  }
}
