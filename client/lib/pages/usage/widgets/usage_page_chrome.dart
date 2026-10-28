import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../services/usage/usage_sync_control.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsagePageHeader extends StatelessWidget {
  const UsagePageHeader({
    required this.state,
    required this.onIncrementalSync,
    required this.onFullSync,
    required this.onCancel,
    required this.onCursor,
    required this.onMaintenance,
    super.key,
  });

  final SessionUsageState state;
  final Future<void> Function() onIncrementalSync;
  final Future<void> Function() onFullSync;
  final VoidCallback onCancel;
  final VoidCallback onCursor;
  final VoidCallback onMaintenance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sessionUsageTitle,
          style: styles.xl.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          l10n.sessionUsageSubtitle,
          style: styles.smColored(cs.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              formatUsageLastSync(context, state.lastSyncAtMs),
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.52),
              ),
            ),
            Text(
              l10n.sessionUsageScopeHint,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.42),
              ),
            ),
            if (state.isSyncing)
              Text(
                key: AppKeys.sessionUsageSyncProgress,
                _progressLabel(context, state.syncProgress),
                style: styles.xs.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _secondaryAction(
          key: AppKeys.sessionUsageCursorButton,
          icon: Icons.cloud_sync_outlined,
          label: l10n.sessionUsageCursorTitle,
          onPressed: onCursor,
        ),
        _secondaryAction(
          key: AppKeys.sessionUsageMaintenanceButton,
          icon: Icons.storage_outlined,
          label: l10n.sessionUsageStorage,
          onPressed: onMaintenance,
        ),
        _syncControl(context),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [summary, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }

  Widget _secondaryAction({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      label: Text(label),
    );
  }

  Widget _syncControl(BuildContext context) {
    final l10n = context.l10n;
    if (state.isSyncing) {
      return Tooltip(
        message: l10n.sessionUsageCancelSyncTooltip,
        child: FilledButton.icon(
          key: AppKeys.sessionUsageCancelSyncButton,
          onPressed: state.isCancelling ? null : onCancel,
          icon: state.isCancelling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.close, size: 18),
          label: Text(
            state.isCancelling
                ? l10n.sessionUsageCancelling
                : l10n.sessionUsageCancelSync,
          ),
        ),
      );
    }
    return Tooltip(
      message: l10n.sessionUsageSyncTooltip,
      child: MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          MenuItemButton(
            key: AppKeys.sessionUsageIncrementalSync,
            leadingIcon: const Icon(Icons.sync, size: 18),
            onPressed: () => onIncrementalSync(),
            child: _menuOption(
              context,
              l10n.sessionUsageSyncIncremental,
              l10n.sessionUsageSyncIncrementalHint,
            ),
          ),
          MenuItemButton(
            key: AppKeys.sessionUsageFullSync,
            leadingIcon: const Icon(Icons.restart_alt, size: 18),
            onPressed: () => onFullSync(),
            child: _menuOption(
              context,
              l10n.sessionUsageSyncFull,
              l10n.sessionUsageSyncFullHint,
            ),
          ),
        ],
        builder: (context, controller, child) => FilledButton.icon(
          key: AppKeys.sessionUsageSyncButton,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.sync, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.sessionUsageSync),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuOption(BuildContext context, String title, String hint) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: styles.sm),
          const SizedBox(height: 1),
          Text(
            hint,
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

String _progressLabel(BuildContext context, UsageSyncProgress? progress) {
  final l10n = context.l10n;
  if (progress == null || progress.targetsTotal == 0) {
    return l10n.sessionUsageSyncPreparing;
  }
  return l10n.sessionUsageSyncProgress(
    progress.targetsDone,
    progress.targetsTotal,
    progress.inserted,
  );
}

class UsageToolbar extends StatelessWidget {
  const UsageToolbar({required this.state, required this.cubit, super.key});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final range in UsageRange.values)
          ChoiceChip(
            label: Text(_rangeLabel(context, range)),
            selected: state.range == range,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => cubit.setRange(range),
          ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(l10n.sessionUsageCliAll),
          selected: state.cli == null,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => cubit.setCli(null),
        ),
        for (final cli in CliTool.values)
          ChoiceChip(
            label: Text(usageCliLabel(cli)),
            selected: state.cli == cli,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => cubit.setCli(cli),
          ),
        const SizedBox(width: 8),
        Text(
          l10n.sessionUsageGroupBy,
          style: styles.xs.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        for (final group in UsageGroupBy.values)
          ChoiceChip(
            label: Text(usageGroupLabel(context, group)),
            selected: state.groupBy == group,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => cubit.setGroupBy(group),
          ),
      ],
    );
  }

  String _rangeLabel(BuildContext context, UsageRange range) {
    final l10n = context.l10n;
    return switch (range) {
      UsageRange.today => l10n.sessionUsageRangeToday,
      UsageRange.sevenDays => l10n.sessionUsageRangeSevenDays,
      UsageRange.thirtyDays => l10n.sessionUsageRangeThirtyDays,
      UsageRange.all => l10n.sessionUsageRangeAll,
    };
  }
}

class UsageFooter extends StatelessWidget {
  const UsageFooter({required this.state, super.key});

  final SessionUsageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Text(
      l10n.sessionUsageShowing(
        state.dashboard.rows.length,
        state.dashboard.totalEventCount,
      ),
      style: styles.xs.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
    );
  }
}
