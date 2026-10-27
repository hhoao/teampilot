import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/usage/usage_store.dart';
import '../../utils/ui/app_keys.dart';

class UsageMaintenanceDialog extends StatefulWidget {
  const UsageMaintenanceDialog({
    required this.stats,
    required this.onCompact,
    required this.onFullSync,
    this.error,
    super.key,
  });

  final UsageStoreStats? stats;
  final Future<bool> Function() onCompact;
  final Future<bool> Function() onFullSync;
  final String? error;

  @override
  State<UsageMaintenanceDialog> createState() => _UsageMaintenanceDialogState();
}

class _UsageMaintenanceDialogState extends State<UsageMaintenanceDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _compact() => _run(widget.onCompact);

  Future<void> _fullSync() => _run(widget.onFullSync);

  Future<void> _run(Future<bool> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = context.l10n.sessionUsageMaintenanceFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stats = widget.stats;
    final error = _error ?? widget.error;
    return AlertDialog(
      key: AppKeys.sessionUsageMaintenanceDialog,
      title: Text(l10n.sessionUsageMaintenanceTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stats == null)
              const LinearProgressIndicator()
            else ...[
              Text(
                l10n.sessionUsageMaintenanceLines(
                  stats.lineCount,
                  stats.eventCount,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.sessionUsageMaintenanceSize(
                  (stats.sizeBytes / 1024).toStringAsFixed(1),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.sessionUsageMaintenanceCompactHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.sessionUsageMaintenanceFullHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        OutlinedButton(
          key: AppKeys.sessionUsageFullSyncButton,
          onPressed: _busy ? null : _fullSync,
          child: Text(l10n.sessionUsageMaintenanceFull),
        ),
        FilledButton(
          key: AppKeys.sessionUsageCompactButton,
          onPressed: _busy || stats == null ? null : _compact,
          child: Text(l10n.sessionUsageMaintenanceCompact),
        ),
      ],
    );
  }
}
