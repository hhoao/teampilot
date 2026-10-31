import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Background scan intervals offered by the usage settings dialog.
const List<int> usageSyncIntervalOptions = [1, 5, 10, 30];

/// Fallback interval used for unset or unknown stored values.
const int usageSyncIntervalDefaultMinutes = 10;

int normalizeUsageSyncInterval(int minutes) =>
    usageSyncIntervalOptions.contains(minutes)
    ? minutes
    : usageSyncIntervalDefaultMinutes;

/// Actions the settings dialog can hand back to the page.
enum UsageSettingsAction { syncNow, maintenance }

/// Data-source settings: whether the page scans automatically and how often.
class UsageSettingsDialog extends StatefulWidget {
  const UsageSettingsDialog({
    required this.autoSyncEnabled,
    required this.intervalMinutes,
    required this.onAutoSyncChanged,
    required this.onIntervalChanged,
    super.key,
  });

  final bool autoSyncEnabled;
  final int intervalMinutes;
  final ValueChanged<bool> onAutoSyncChanged;
  final ValueChanged<int> onIntervalChanged;

  @override
  State<UsageSettingsDialog> createState() => _UsageSettingsDialogState();
}

class _UsageSettingsDialogState extends State<UsageSettingsDialog> {
  late bool _enabled = widget.autoSyncEnabled;
  late int _minutes = normalizeUsageSyncInterval(widget.intervalMinutes);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final muted = cs.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      key: AppKeys.sessionUsageSettingsDialog,
      title: Text(l10n.sessionUsageSettings),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sessionUsageDataSource, style: styles.mdBold),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.sessionUsageAutoScan, style: styles.md),
                  ),
                  Switch(
                    key: AppKeys.sessionUsageAutoScanSwitch,
                    value: _enabled,
                    onChanged: _setEnabled,
                  ),
                ],
              ),
              Text(
                l10n.sessionUsageAutoScanHint(_minutes),
                style: styles.xs.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.sessionUsageScanInterval, style: styles.md),
                  ),
                  DropdownButton<int>(
                    key: AppKeys.sessionUsageScanInterval,
                    value: _minutes,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(10),
                    onChanged: _enabled ? _setInterval : null,
                    items: [
                      for (final minutes in usageSyncIntervalOptions)
                        DropdownMenuItem(
                          value: minutes,
                          child: Text(
                            l10n.sessionUsageIntervalMinutes(minutes),
                            style: styles.md.copyWith(color: muted),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: AppKeys.sessionUsageSyncNowButton,
                onPressed: () => Navigator.of(
                  context,
                ).pop(UsageSettingsAction.syncNow),
                icon: const Icon(Icons.sync, size: 16),
                label: Text(l10n.sessionUsageSyncNow),
              ),
              const Divider(height: 28),
              InkWell(
                key: AppKeys.sessionUsageSettingsStorageEntry,
                onTap: () => Navigator.of(
                  context,
                ).pop(UsageSettingsAction.maintenance),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 18,
                        color: muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.sessionUsageMaintenanceEntry,
                          style: styles.md,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    widget.onAutoSyncChanged(value);
  }

  void _setInterval(int? value) {
    if (value == null) return;
    setState(() => _minutes = value);
    widget.onIntervalChanged(value);
  }
}
