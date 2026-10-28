import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/cursor_usage_import.dart';
import '../../services/usage/usage_store.dart';
import '../../utils/ui/app_keys.dart';

class UsageMaintenanceDialog extends StatefulWidget {
  const UsageMaintenanceDialog({
    required this.stats,
    required this.onCompact,
    required this.onFullSync,
    this.cursorStatus = const CursorUsageImportStatus(),
    this.cursorBusy = false,
    this.onImportCursorCsv,
    this.onSyncCursor,
    this.onClearCursor,
    this.error,
    super.key,
  });

  final UsageStoreStats? stats;
  final Future<bool> Function() onCompact;
  final Future<bool> Function() onFullSync;
  final CursorUsageImportStatus cursorStatus;
  final bool cursorBusy;
  final Future<String?> Function()? onImportCursorCsv;
  final Future<String?> Function()? onSyncCursor;
  final Future<String?> Function()? onClearCursor;
  final String? error;

  @override
  State<UsageMaintenanceDialog> createState() => _UsageMaintenanceDialogState();
}

class _UsageMaintenanceDialogState extends State<UsageMaintenanceDialog> {
  bool _busy = false;
  String? _error;
  String? _cursorErrorText;

  Future<void> _compact() => _run(widget.onCompact);

  Future<void> _fullSync() => _run(widget.onFullSync);

  Future<void> _runCursor(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _cursorErrorText = null;
    });
    final error = await action();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _cursorErrorText = error.isEmpty ? null : error;
    });
  }

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
        child: SingleChildScrollView(
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
              if (widget.onImportCursorCsv != null ||
                  widget.onSyncCursor != null) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.sessionUsageCursorTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.sessionUsageCursorHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.cursorStatus.hasData
                      ? l10n.sessionUsageCursorImported(
                          widget.cursorStatus.eventCount,
                        )
                      : l10n.sessionUsageCursorNoData,
                ),
                if (widget.cursorStatus.lastSyncAtMs != null ||
                    widget.cursorStatus.lastImportAtMs != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.sessionUsageCursorLastUpdated(
                      _formatCursorTime(
                        context,
                        widget.cursorStatus.lastSyncAtMs ??
                            widget.cursorStatus.lastImportAtMs!,
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (widget.onImportCursorCsv != null)
                      OutlinedButton.icon(
                        key: AppKeys.sessionUsageCursorImportButton,
                        onPressed: _busy || widget.cursorBusy
                            ? null
                            : () => _runCursor(widget.onImportCursorCsv!),
                        icon: const Icon(Icons.file_upload_outlined, size: 16),
                        label: Text(l10n.sessionUsageCursorImport),
                      ),
                    if (widget.onSyncCursor != null)
                      OutlinedButton.icon(
                        key: AppKeys.sessionUsageCursorSyncButton,
                        onPressed: _busy || widget.cursorBusy
                            ? null
                            : () => _runCursor(widget.onSyncCursor!),
                        icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                        label: Text(l10n.sessionUsageCursorSync),
                      ),
                    if (widget.onClearCursor != null &&
                        widget.cursorStatus.hasData)
                      TextButton(
                        key: AppKeys.sessionUsageCursorClearButton,
                        onPressed: _busy || widget.cursorBusy
                            ? null
                            : () => _runCursor(widget.onClearCursor!),
                        child: Text(l10n.sessionUsageCursorClear),
                      ),
                  ],
                ),
                if (widget.cursorBusy || _cursorErrorText != null) ...[
                  const SizedBox(height: 6),
                  if (widget.cursorBusy)
                    const LinearProgressIndicator()
                  else
                    Text(
                      _cursorErrorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
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

String _formatCursorTime(BuildContext context, int timestampMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final material = MaterialLocalizations.of(context);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${material.formatShortDate(date)} $time';
}
