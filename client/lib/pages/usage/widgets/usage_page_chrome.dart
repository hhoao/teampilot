import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsagePageHeader extends StatelessWidget {
  const UsagePageHeader({required this.state, required this.onSync, super.key});

  final SessionUsageState state;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
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
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: l10n.sessionUsageSyncTooltip,
          child: FilledButton.icon(
            key: AppKeys.sessionUsageSyncButton,
            onPressed: state.isSyncing ? null : onSync,
            icon: state.isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(
              state.isSyncing
                  ? l10n.sessionUsageSyncing
                  : l10n.sessionUsageSync,
            ),
          ),
        ),
      ],
    );
  }
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
        for (final cli in const [
          CliTool.claude,
          CliTool.codex,
          CliTool.opencode,
        ])
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
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          l10n.sessionUsageShowing(
            state.dashboard.rows.length,
            state.dashboard.totalEventCount,
          ),
          style: styles.xs.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        Wrap(
          spacing: 10,
          children: [
            Text(
              l10n.sessionUsageFooterJsonl,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.42),
              ),
            ),
            Text(
              l10n.sessionUsageFooterManual,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
