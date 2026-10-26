import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'widgets/usage_cli_breakdown.dart';
import 'widgets/usage_detail_table.dart';
import 'widgets/usage_page_chrome.dart';
import 'widgets/usage_page_states.dart';
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
                UsagePageHeader(state: state, onSync: cubit.sync),
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
        return UsageLoadError(onRetry: cubit.reload);
      }
      return UsageEmptyState(
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
          UsageToolbar(state: state, cubit: cubit),
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
                selectedCli: state.cli,
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
          UsageFooter(state: state),
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
      return UsageSyncErrorBanner(
        message: l10n.sessionUsageSyncFatal,
        onRetry: cubit.sync,
        onDismiss: cubit.clearSyncErrors,
      );
    }
    if (state.syncErrors.isNotEmpty) {
      return UsageSyncErrorBanner(
        message: l10n.sessionUsageSyncPartial(state.syncErrors.length),
        onRetry: cubit.sync,
        onDismiss: cubit.clearSyncErrors,
      );
    }
    if (state.errorMessage != null && state.hasData) {
      return UsageSyncErrorBanner(
        message: l10n.sessionUsageLoadFailed,
        onRetry: cubit.reload,
        onDismiss: cubit.clearLoadError,
      );
    }
    return null;
  }
}
