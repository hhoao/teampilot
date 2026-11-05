import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/app_settings_repository.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'usage_maintenance_dialog.dart';
import 'usage_pricing_dialog.dart';
import 'usage_settings_dialog.dart';
import 'widgets/usage_detail_table.dart';
import 'widgets/usage_filter_bar.dart';
import 'widgets/usage_heatmap_card.dart';
import 'widgets/usage_page_chrome.dart';
import 'widgets/usage_page_states.dart';
import 'widgets/usage_summary_cards.dart';

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

class _SessionUsagePageState extends State<SessionUsagePage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  Timer? _autoSyncTimer;
  Timer? _liveRangeTimer;
  bool _appActive = true;
  late final AppSettingsRepository _settings;
  late final Future<void> _settingsReady;
  bool _autoSyncEnabled = true;
  int _autoSyncIntervalMinutes = usageSyncIntervalDefaultMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;

    _settings = context.read<AppSettingsRepository>();
    _settingsReady = _loadSyncSettings();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cubit = context.read<SessionUsageCubit>();
      await cubit.ensureLoaded();
      await _settingsReady;
      if (!mounted || !_autoSyncActive || !_appActive) return;
      await cubit.syncIfStale(ttl: _autoSyncTtl);
    });

    // The cubit outlives this State, so a live range set before the page was
    // remounted never produces a liveEnd transition to listen for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncLiveRangeTimer(context.read<SessionUsageCubit>().state.liveEnd);
    });
  }

  bool get _autoSyncActive => widget.autoSync && _autoSyncEnabled;

  Future<void> _loadSyncSettings() async {
    final enabled = await _settings.loadUsageAutoSyncEnabled();
    final minutes = await _settings.loadUsageSyncIntervalMinutes();
    if (!mounted) return;
    setState(() {
      _autoSyncEnabled = enabled;
      _autoSyncIntervalMinutes = normalizeUsageSyncInterval(minutes);
    });
    _restartAutoSyncTimer();
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    if (!_autoSyncActive) return;
    final interval = Duration(minutes: _autoSyncIntervalMinutes);
    _autoSyncTimer = Timer.periodic(interval, (_) {
      if (!mounted || !_appActive) return;
      unawaited(context.read<SessionUsageCubit>().syncIfStale(ttl: interval));
    });
  }

  Future<void> _setAutoSyncEnabled(bool value) async {
    setState(() => _autoSyncEnabled = value);
    _restartAutoSyncTimer();
    await _settings.saveUsageAutoSyncEnabled(value);
  }

  Future<void> _setAutoSyncInterval(int minutes) async {
    setState(() => _autoSyncIntervalMinutes = minutes);
    _restartAutoSyncTimer();
    await _settings.saveUsageSyncIntervalMinutes(minutes);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _autoSyncActive) {
      unawaited(
        context.read<SessionUsageCubit>().syncIfStale(ttl: _autoSyncTtl),
      );
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _liveRangeTimer?.cancel();
    _liveRangeTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters(SessionUsageCubit cubit) {
    _searchController.clear();
    cubit.resetFilters();
  }

  /// Keeps a live-end custom range moving while the page is open.
  void _syncLiveRangeTimer(bool live) {
    if (live && _liveRangeTimer == null) {
      _liveRangeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted || !_appActive) return;
        context.read<SessionUsageCubit>().refreshRangeNow();
      });
      return;
    }
    if (!live) {
      _liveRangeTimer?.cancel();
      _liveRangeTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = BlocListener<SessionUsageCubit, SessionUsageState>(
      listenWhen: (previous, current) => previous.liveEnd != current.liveEnd,
      listener: (context, state) => _syncLiveRangeTimer(state.liveEnd),
      child: BlocListener<SessionUsageCubit, SessionUsageState>(
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
                  previous.isComputing != current.isComputing ||
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
                    onIncrementalSync: () => cubit.sync(),
                    onFullSync: cubit.fullSync,
                    onCancel: cubit.cancelSync,
                    onSettings: () => _openSettings(cubit),
                  ),
                  if (_errorBanner(context, cubit, state)
                      case final banner?) ...[
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
      ),
    );

    if (widget.embedded) return content;
    return Padding(padding: WorkspacePaneInsets.page, child: content);
  }

  Future<void> _openSettings(SessionUsageCubit cubit) async {
    final action = await showDialog<UsageSettingsAction>(
      context: context,
      builder: (context) => UsageSettingsDialog(
        autoSyncEnabled: _autoSyncEnabled,
        intervalMinutes: _autoSyncIntervalMinutes,
        onAutoSyncChanged: _setAutoSyncEnabled,
        onIntervalChanged: _setAutoSyncInterval,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case UsageSettingsAction.syncNow:
        unawaited(cubit.sync());
      case UsageSettingsAction.maintenance:
        await _openMaintenance(cubit);
    }
  }

  Future<void> _openMaintenance(SessionUsageCubit cubit) async {
    await cubit.loadMaintenanceStats();
    if (!mounted) return;
    final compactedMessage = context.l10n.sessionUsageMaintenanceCompacted;
    final fullDoneMessage = context.l10n.sessionUsageMaintenanceFullDone;
    await showDialog<void>(
      context: context,
      builder: (context) => UsageMaintenanceDialog(
        stats: cubit.state.usageStats,
        error: cubit.state.maintenanceError,
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
          UsageFilterBar(state: state, cubit: cubit),
          const SizedBox(height: 14),
          BlocSelector<SessionUsageCubit, SessionUsageState, int>(
            selector: (state) => Object.hash(
              state.dashboard.summary,
              Object.hashAll(state.dashboard.chart),
              state.pricingCorrupted,
            ),
            builder: (context, _) => UsageSummaryCards(
              dashboard: cubit.state.dashboard,
              nowMs: nowMs,
              pricingCorrupted: cubit.state.pricingCorrupted,
              onManagePricing: () => _openPricing(cubit),
            ),
          ),
          const SizedBox(height: 14),
          BlocSelector<SessionUsageCubit, SessionUsageState, int>(
            selector: (state) => Object.hashAll(state.dashboard.heatmap),
            builder: (context, _) => UsageHeatmapCard(
              days: cubit.state.dashboard.heatmap,
              nowMs: nowMs,
            ),
          ),
          const SizedBox(height: 14),
          UsageDetailTable(
            dashboard: dashboard,
            groupBy: state.groupBy,
            searchController: _searchController,
            onQueryChanged: cubit.setQuery,
            onGroupByChanged: cubit.setGroupBy,
            onResetFilters: () => _resetFilters(cubit),
            isComputing: state.isComputing,
            resetKey:
                '${state.range.name}|${state.customStartMs ?? ''}|'
                '${state.customEndMs ?? ''}|${state.liveEnd}|'
                '${state.cli?.name ?? ''}|${state.groupBy.name}|${state.query}',
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
