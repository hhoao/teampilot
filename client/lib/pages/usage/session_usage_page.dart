import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/team_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'usage_format.dart';
import 'widgets/usage_cli_breakdown.dart';
import 'widgets/usage_detail_table.dart';
import 'widgets/usage_summary_cards.dart';
import 'widgets/usage_trend_chart.dart';

class SessionUsagePage extends StatefulWidget {
  const SessionUsagePage({this.embedded = false, super.key});

  /// When true, the workspace-home shell already applied pane padding.
  final bool embedded;

  @override
  State<SessionUsagePage> createState() => _SessionUsagePageState();
}

class _SessionUsagePageState extends State<SessionUsagePage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SessionUsageCubit>().ensureLoaded());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters(SessionUsageCubit cubit) {
    _searchController.clear();
    cubit.resetFilters();
  }

  @override
  Widget build(BuildContext context) {
    final content = BlocListener<SessionUsageCubit, SessionUsageState>(
      listenWhen: (previous, current) =>
          previous.isSyncing &&
          !current.isSyncing &&
          !current.syncFailed &&
          current.syncErrors.isEmpty &&
          current.lastSyncResult != null,
      listener: (context, state) {
        AppToast.show(
          context,
          message: context.l10n.sessionUsageSyncedToast,
          variant: TpToastVariant.success,
        );
      },
      child: BlocBuilder<SessionUsageCubit, SessionUsageState>(
        builder: (context, state) {
          final cubit = context.read<SessionUsageCubit>();
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final body = _buildBody(context, cubit, state, nowMs);
          return KeyedSubtree(
            key: AppKeys.sessionUsagePage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(state: state, onSync: cubit.sync),
                if (_errorBanner(context, cubit, state) case final banner?) ...[
                  const SizedBox(height: 12),
                  banner,
                ],
                const SizedBox(height: 16),
                Expanded(child: body),
              ],
            ),
          );
        },
      ),
    );

    if (widget.embedded) return content;
    return Padding(padding: WorkspacePaneInsets.page, child: content);
  }

  Widget _buildBody(
    BuildContext context,
    SessionUsageCubit cubit,
    SessionUsageState state,
    int nowMs,
  ) {
    if (!state.hasData) {
      if (state.status == SessionUsageStatus.initial ||
          state.status == SessionUsageStatus.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.status == SessionUsageStatus.error) {
        return _LoadError(onRetry: cubit.reload);
      }
      return _EmptyUsage(
        onSync: cubit.sync,
        onReset: () => _resetFilters(cubit),
      );
    }

    final dashboard = state.dashboard;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UsageToolbar(state: state, cubit: cubit),
          const SizedBox(height: 14),
          UsageSummaryCards(dashboard: dashboard, nowMs: nowMs),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = UsageTrendChart(
                days: dashboard.chart,
                nowMs: nowMs,
                selectedCli: state.cli,
              );
              final breakdown = UsageCliBreakdown(
                slices: dashboard.cliSlices,
                summary: dashboard.summary,
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [chart, const SizedBox(height: 12), breakdown],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: chart),
                    const SizedBox(width: 12),
                    SizedBox(width: 300, child: breakdown),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          UsageDetailTable(
            dashboard: dashboard,
            groupBy: state.groupBy,
            searchController: _searchController,
            onQueryChanged: cubit.setQuery,
            onResetFilters: () => _resetFilters(cubit),
          ),
          const SizedBox(height: 10),
          _Footer(state: state),
        ],
      ),
    );
  }

  Widget? _errorBanner(
    BuildContext context,
    SessionUsageCubit cubit,
    SessionUsageState state,
  ) {
    final l10n = context.l10n;
    if (state.syncFailed) {
      return _SyncErrorBanner(
        message: l10n.sessionUsageSyncFatal,
        onRetry: cubit.sync,
        onDismiss: cubit.clearSyncErrors,
      );
    }
    if (state.syncErrors.isNotEmpty) {
      return _SyncErrorBanner(
        message: l10n.sessionUsageSyncPartial(state.syncErrors.length),
        onRetry: cubit.sync,
        onDismiss: cubit.clearSyncErrors,
      );
    }
    if (state.errorMessage != null && state.hasData) {
      return _SyncErrorBanner(
        message: l10n.sessionUsageLoadFailed,
        onRetry: cubit.reload,
        onDismiss: cubit.clearLoadError,
      );
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onSync});

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

class _UsageToolbar extends StatelessWidget {
  const _UsageToolbar({required this.state, required this.cubit});

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
        Text(
          l10n.sessionUsageCliAll,
          style: styles.xs.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
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

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

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

class _EmptyUsage extends StatelessWidget {
  const _EmptyUsage({required this.onSync, required this.onReset});

  final Future<void> Function() onSync;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          key: AppKeys.sessionUsageEmptyState,
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 22),
          decoration: workspaceCardDecoration(
            cs,
            radius: 14,
          ).copyWith(color: cs.workspaceCard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TpEmptyState(
                icon: Icons.insights_outlined,
                title: l10n.sessionUsageEmptyTitle,
                hint: l10n.sessionUsageEmptyBody,
                actionLabel: l10n.sessionUsageSync,
                onAction: onSync,
                centered: true,
              ),
              TextButton(
                onPressed: onReset,
                child: Text(l10n.sessionUsageResetFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: workspaceCardDecoration(
          cs,
          radius: 14,
        ).copyWith(color: cs.workspaceCard),
        child: TpEmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.sessionUsageLoadFailed,
          actionLabel: l10n.sessionUsageRetry,
          onAction: onRetry,
          centered: true,
        ),
      ),
    );
  }
}

class _SyncErrorBanner extends StatelessWidget {
  const _SyncErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Container(
      key: AppKeys.sessionUsageErrorBanner,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: styles.sm.copyWith(color: cs.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.sessionUsageRetry)),
          IconButton(
            tooltip: l10n.sessionUsageDismiss,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
