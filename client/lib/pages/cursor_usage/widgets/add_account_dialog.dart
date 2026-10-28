import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';

/// Returns the pasted value and an optional label, or null when cancelled.
Future<(String, String?)?> showAddCursorAccountDialog(BuildContext context) {
  final tokenController = TextEditingController();
  final labelController = TextEditingController();
  return showDialog<(String, String?)>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.cursorUsageAddAccountTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tokenController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.cursorUsageAddAccountField,
                helperText: l10n.cursorUsageAddAccountHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: l10n.cursorUsageAddAccountLabel,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final raw = tokenController.text.trim();
              if (raw.isEmpty) return;
              final label = labelController.text.trim();
              Navigator.of(context).pop((raw, label.isEmpty ? null : label));
            },
            child: Text(l10n.cursorUsageAddAccountConfirm),
          ),
        ],
      );
    },
  );
}
