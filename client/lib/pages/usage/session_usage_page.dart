import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/usage/cursor_usage_sync_service.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'usage_maintenance_dialog.dart';
import 'usage_pricing_dialog.dart';
import 'widgets/usage_cli_breakdown.dart';
import 'widgets/usage_cost_card.dart';
import 'widgets/usage_detail_table.dart';
import 'widgets/usage_page_chrome.dart';
import 'widgets/usage_page_states.dart';
import 'widgets/usage_summary_cards.dart';
import 'widgets/usage_trend_chart.dart';

class SessionUsagePage extends StatefulWidget {
  const SessionUsagePage({
    this.embedded = false,
    this.autoSync = true,
    super.key,
  });

  /// When true, the workspace-home shell already applied pane padding.
  final bool embedded;

  /// Runs stale checks on open, on app resume, and every 10 minutes.
  final bool autoSync;

  @override
  State<SessionUsagePage> createState() => _SessionUsagePageState();
}

const Duration _autoSyncTtl = Duration(minutes: 5);
const Duration _autoSyncInterval = Duration(minutes: 10);

class _SessionUsagePageState extends State<SessionUsagePage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  Timer? _autoSyncTimer;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;

    if (widget.autoSync) {
      _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
        if (!mounted || !_appActive) return;
        unawaited(
          context.read<SessionUsageCubit>().syncIfStale(ttl: _autoSyncTtl),
        );
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cubit = context.read<SessionUsageCubit>();
      await cubit.ensureLoaded();
      if (!mounted || !widget.autoSync || !_appActive) return;
      await cubit.syncIfStale(ttl: _autoSyncTtl);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && widget.autoSync) {
      unawaited(
        context.read<SessionUsageCubit>().syncIfStale(ttl: _autoSyncTtl),
      );
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    WidgetsBinding.instance.removeObserver(this);
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
          previous.isSyncing && !current.isSyncing,
      listener: (context, state) {
        if (state.syncCancelled) {
          AppToast.show(
            context,
            message: context.l10n.sessionUsageSyncCancelled,
            variant: TpToastVariant.info,
          );
          return;
        }
        if (state.lastSyncManual &&
            !state.syncFailed &&
            state.syncErrors.isEmpty &&
            state.lastSyncResult != null) {
          AppToast.show(
            context,
            message: context.l10n.sessionUsageSyncedToast,
            variant: TpToastVariant.success,
          );
        }
      },
      child: BlocBuilder<SessionUsageCubit, SessionUsageState>(
        builder: (context, state) {
          final cubit = context.read<SessionUsageCubit>();
          final body = BlocBuilder<SessionUsageCubit, SessionUsageState>(
            buildWhen: (previous, current) =>
                previous.status != current.status ||
                previous.dashboard != current.dashboard ||
                previous.errorMessage != current.errorMessage ||
                previous.pricingCorrupted != current.pricingCorrupted,
            builder: (context, bodyState) => _buildBody(
              context,
              cubit,
              bodyState,
              DateTime.now().millisecondsSinceEpoch,
            ),
          );
          return KeyedSubtree(
            key: AppKeys.sessionUsagePage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UsagePageHeader(
                  state: state,
                  onSync: () => cubit.sync(),
                  onCancel: cubit.cancelSync,
                ),
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

  Future<void> _openMaintenance(SessionUsageCubit cubit) async {
    await cubit.loadMaintenanceStats();
    await cubit.loadCursorStatus();
    if (!mounted) return;
    final compactedMessage = context.l10n.sessionUsageMaintenanceCompacted;
    final fullDoneMessage = context.l10n.sessionUsageMaintenanceFullDone;
    await showDialog<void>(
      context: context,
      builder: (context) => UsageMaintenanceDialog(
        stats: cubit.state.usageStats,
        error: cubit.state.maintenanceError,
        cursorStatus: cubit.state.cursorStatus,
        cursorBusy: cubit.state.cursorBusy,
        onImportCursorCsv: () => _importCursorCsv(cubit),
        onSyncCursor: () => _syncCursorUsage(cubit),
        onClearCursor: () => _clearCursorUsage(cubit),
        onCompact: () async {
          final ok = await cubit.compactUsage();
          if (ok) {
            AppToast.showGlobal(
              message: compactedMessage,
              variant: TpToastVariant.success,
            );
          }
          return ok;
        },
        onFullSync: () async {
          await cubit.fullSync();
          final ok =
              !cubit.state.syncFailed &&
              cubit.state.syncErrors.isEmpty &&
              !cubit.state.syncCancelled;
          if (ok) {
            AppToast.showGlobal(
              message: fullDoneMessage,
              variant: TpToastVariant.success,
            );
          }
          return ok;
        },
      ),
    );
  }

  Future<String?> _importCursorCsv(SessionUsageCubit cubit) async {
    final bytes = await _pickCursorCsv();
    if (bytes == null) return '';
    String text;
    try {
      text = utf8.decode(bytes);
    } on Object {
      if (!mounted) return '';
      return context.l10n.sessionUsageCursorInvalidCsv;
    }
    final result = await cubit.importCursorCsv(text);
    if (!mounted) return '';
    if (result == null) return _cursorErrorText(cubit.state.cursorError);
    AppToast.showGlobal(
      message: context.l10n.sessionUsageCursorImportedToast(
        result.inserted + result.updated,
      ),
      variant: TpToastVariant.success,
    );
    return null;
  }

  Future<String?> _syncCursorUsage(SessionUsageCubit cubit) async {
    final result = await cubit.syncCursorUsage();
    if (!mounted) return '';
    if (result == null) return _cursorErrorText(cubit.state.cursorError);
    AppToast.showGlobal(
      message: context.l10n.sessionUsageCursorSyncedToast(
        result.inserted + result.updated,
      ),
      variant: TpToastVariant.success,
    );
    return null;
  }

  Future<String?> _clearCursorUsage(SessionUsageCubit cubit) async {
    final ok = await cubit.clearCursorUsage();
    if (!mounted) return '';
    if (!ok) return _cursorErrorText(cubit.state.cursorError);
    AppToast.showGlobal(
      message: context.l10n.sessionUsageCursorCleared,
      variant: TpToastVariant.info,
    );
    return null;
  }

  Future<List<int>?> _pickCursorCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return null;
    return file.bytes ?? const <int>[];
  }

  String _cursorErrorText(CursorUsageSyncError? error) {
    final l10n = context.l10n;
    return switch (error) {
      CursorUsageSyncError.login => l10n.sessionUsageCursorLoginRequired,
      CursorUsageSyncError.rateLimited => l10n.sessionUsageCursorRateLimited,
      CursorUsageSyncError.network => l10n.sessionUsageCursorNetworkFailed,
      CursorUsageSyncError.invalidCsv => l10n.sessionUsageCursorInvalidCsv,
      CursorUsageSyncError.http || null => l10n.sessionUsageCursorFailed,
    };
  }

  Future<void> _openPricing(SessionUsageCubit cubit) async {
    await showDialog<void>(
      context: context,
      builder: (context) => UsagePricingDialog(
        initialRules: cubit.state.pricing.userRules,
        onSave: (rules) async {
          await cubit.savePricing(rules);
          final ok = cubit.state.pricingError == null;
          if (ok && context.mounted) {
            AppToast.show(
              context,
              message: context.l10n.sessionUsagePricingSaved,
              variant: TpToastVariant.success,
            );
          }
          return ok;
        },
        onReset: () async {
          await cubit.resetPricing();
          final ok = cubit.state.pricingError == null;
          if (ok && context.mounted) {
            AppToast.show(
              context,
              message: context.l10n.sessionUsagePricingSaved,
              variant: TpToastVariant.success,
            );
          }
          return ok;
        },
      ),
    );
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
          const SizedBox(height: 12),
          UsageCostCard(
            summary: dashboard.summary,
            corrupted: state.pricingCorrupted,
            onManagePricing: () => _openPricing(cubit),
          ),
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
          UsageFooter(
            state: state,
            onMaintenance: () => _openMaintenance(cubit),
            onCursor: () => _openMaintenance(cubit),
          ),
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
