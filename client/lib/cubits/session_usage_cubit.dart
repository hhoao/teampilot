import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/cursor_usage_account.dart';
import '../models/session_usage.dart';
import '../models/session_usage_dashboard.dart';
import '../models/session_usage_pricing.dart';
import '../models/team_config.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/usage_dashboard_engine.dart';
import '../services/usage/usage_aggregator.dart';
import '../services/usage/usage_pricing_store.dart';
import '../services/usage/usage_store.dart';
import '../services/usage/usage_sync_control.dart';
import '../utils/logging/logger.dart';

enum SessionUsageStatus { initial, loading, ready, error }

final class SessionUsageState extends Equatable {
  SessionUsageState({
    this.status = SessionUsageStatus.initial,
    this.dashboard = const UsageDashboard(),
    this.range = UsageRange.all,
    this.customStartMs,
    this.customEndMs,
    this.liveEnd = false,
    this.cli,
    this.groupBy = UsageGroupBy.session,
    this.query = '',
    this.isSyncing = false,
    this.isComputing = false,
    this.lastSyncAtMs,
    this.lastSyncResult,
    List<UsageSyncError> syncErrors = const [],
    this.syncFailed = false,
    this.syncProgress,
    this.isCancelling = false,
    this.syncCancelled = false,
    this.lastSyncManual = true,
    this.pricing = const UsagePricingCatalog(),
    this.pricingSaving = false,
    this.pricingCorrupted = false,
    this.pricingError,
    this.usageStats,
    this.maintenanceBusy = false,
    this.maintenanceError,
    this.errorMessage,
    this.cursorAccountId,
    List<CursorUsageAccount> cursorAccounts = const [],
  }) : syncErrors = List.unmodifiable(syncErrors),
       cursorAccounts = List.unmodifiable(cursorAccounts);

  final SessionUsageStatus status;
  final UsageDashboard dashboard;
  final UsageRange range;
  final int? customStartMs;
  final int? customEndMs;
  final bool liveEnd;
  final CliTool? cli;
  final UsageGroupBy groupBy;
  final String query;
  final bool isSyncing;
  final bool isComputing;
  final int? lastSyncAtMs;
  final UsageSyncResult? lastSyncResult;
  final List<UsageSyncError> syncErrors;
  final bool syncFailed;
  final UsageSyncProgress? syncProgress;
  final bool isCancelling;
  final bool syncCancelled;
  final bool lastSyncManual;
  final UsagePricingCatalog pricing;
  final bool pricingSaving;
  final bool pricingCorrupted;
  final String? pricingError;
  final UsageStoreStats? usageStats;
  final bool maintenanceBusy;
  final String? maintenanceError;
  final String? errorMessage;

  /// Cursor account filter; null means every account combined.
  final String? cursorAccountId;

  /// Accounts offered by the cursor filter, discovered from provider homes.
  final List<CursorUsageAccount> cursorAccounts;

  bool get hasData => dashboard.totalEventCount > 0;
  bool get hasSyncProblem => syncErrors.isNotEmpty || syncFailed;

  SessionUsageState copyWith({
    SessionUsageStatus? status,
    UsageDashboard? dashboard,
    UsageRange? range,
    int? customStartMs,
    int? customEndMs,
    bool clearCustomRange = false,
    bool? liveEnd,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
    bool? isSyncing,
    bool? isComputing,
    int? lastSyncAtMs,
    UsageSyncResult? lastSyncResult,
    bool clearLastSyncResult = false,
    List<UsageSyncError>? syncErrors,
    bool? syncFailed,
    UsageSyncProgress? syncProgress,
    bool clearSyncProgress = false,
    bool? isCancelling,
    bool? syncCancelled,
    bool? lastSyncManual,
    UsagePricingCatalog? pricing,
    bool? pricingSaving,
    bool? pricingCorrupted,
    String? pricingError,
    bool clearPricingError = false,
    UsageStoreStats? usageStats,
    bool? maintenanceBusy,
    String? maintenanceError,
    bool clearMaintenanceError = false,
    String? errorMessage,
    bool clearError = false,
    String? cursorAccountId,
    bool clearCursorAccount = false,
    List<CursorUsageAccount>? cursorAccounts,
  }) {
    return SessionUsageState(
      status: status ?? this.status,
      dashboard: dashboard ?? this.dashboard,
      range: range ?? this.range,
      customStartMs: clearCustomRange
          ? null
          : (customStartMs ?? this.customStartMs),
      customEndMs: clearCustomRange ? null : (customEndMs ?? this.customEndMs),
      liveEnd: liveEnd ?? this.liveEnd,
      cli: clearCli ? null : (cli ?? this.cli),
      groupBy: groupBy ?? this.groupBy,
      query: query ?? this.query,
      isSyncing: isSyncing ?? this.isSyncing,
      isComputing: isComputing ?? this.isComputing,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      lastSyncResult: clearLastSyncResult
          ? null
          : (lastSyncResult ?? this.lastSyncResult),
      syncErrors: syncErrors ?? this.syncErrors,
      syncFailed: syncFailed ?? this.syncFailed,
      syncProgress: clearSyncProgress
          ? null
          : (syncProgress ?? this.syncProgress),
      isCancelling: isCancelling ?? this.isCancelling,
      syncCancelled: syncCancelled ?? this.syncCancelled,
      lastSyncManual: lastSyncManual ?? this.lastSyncManual,
      pricing: pricing ?? this.pricing,
      pricingSaving: pricingSaving ?? this.pricingSaving,
      pricingCorrupted: pricingCorrupted ?? this.pricingCorrupted,
      pricingError: clearPricingError
          ? null
          : (pricingError ?? this.pricingError),
      usageStats: usageStats ?? this.usageStats,
      maintenanceBusy: maintenanceBusy ?? this.maintenanceBusy,
      maintenanceError: clearMaintenanceError
          ? null
          : (maintenanceError ?? this.maintenanceError),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      cursorAccountId: clearCursorAccount
          ? null
          : (cursorAccountId ?? this.cursorAccountId),
      cursorAccounts: cursorAccounts ?? this.cursorAccounts,
    );
  }

  @override
  List<Object?> get props => [
    status,
    dashboard,
    range,
    customStartMs,
    customEndMs,
    liveEnd,
    cli,
    groupBy,
    query,
    isSyncing,
    isComputing,
    lastSyncAtMs,
    lastSyncResult,
    syncErrors,
    syncFailed,
    syncProgress,
    isCancelling,
    syncCancelled,
    lastSyncManual,
    pricing,
    pricingSaving,
    pricingCorrupted,
    pricingError,
    usageStats,
    maintenanceBusy,
    maintenanceError,
    errorMessage,
    cursorAccountId,
    cursorAccounts,
  ];
}

/// Cached-event loader + manual sync state for the usage page.
///
/// The cubit never scans CLI transcripts itself; [syncAll] does that and the
/// cubit reloads the JSONL cache afterwards. Filters only recompute in memory.
final class SessionUsageCubit extends Cubit<SessionUsageState> {
  SessionUsageCubit({
    required Future<List<SessionUsageEvent>> Function() loadEvents,
    Future<List<CursorUsageAccount>> Function()? loadCursorAccounts,
    Future<void> Function(
      UsageRange range,
      int? startMs,
      int? endMs,
      bool full,
    )?
    syncCursorUsage,
    required Future<UsageSyncResult> Function() syncAll,
    UsageSyncHandle Function()? startSync,
    UsageSyncHandle Function()? startFullSync,
    Future<UsagePricingLoad> Function()? loadPricing,
    Future<void> Function(List<UsagePriceRule> rules)? savePricing,
    Future<UsageStoreStats> Function()? loadUsageStats,
    Future<UsageCompactResult> Function({int? retainAfterMs})? compactUsage,
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    Stream<void>? storageChanges,
    DateTime Function()? now,
    this.isolateThreshold = 4000,
  }) : _loadEvents = loadEvents,
       _loadCursorAccounts = loadCursorAccounts,
       _syncCursorUsage = syncCursorUsage,
       _syncAll = syncAll,
       _startSync = startSync,
       _startFullSync = startFullSync,
       _loadPricing = loadPricing,
       _savePricing = savePricing,
       _loadUsageStats = loadUsageStats,
       _compactUsage = compactUsage,
       _loadSessions = loadSessions,
       _loadTeams = loadTeams,
       _now = now ?? DateTime.now,
       super(SessionUsageState()) {
    _engine = UsageDashboardEngine(isolateThreshold: isolateThreshold);
    _storageSub = storageChanges?.listen((_) {
      unawaited(reload());
    });
  }

  final Future<List<SessionUsageEvent>> Function() _loadEvents;
  final Future<List<CursorUsageAccount>> Function()? _loadCursorAccounts;
  final Future<void> Function(
    UsageRange range,
    int? startMs,
    int? endMs,
    bool full,
  )?
  _syncCursorUsage;
  int _cursorSyncGeneration = 0;
  Future<void>? _cursorSyncFlight;
  final Future<UsageSyncResult> Function() _syncAll;
  final UsageSyncHandle Function()? _startSync;
  final UsageSyncHandle Function()? _startFullSync;
  final Future<UsagePricingLoad> Function()? _loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules)? _savePricing;
  final Future<UsageStoreStats> Function()? _loadUsageStats;
  final Future<UsageCompactResult> Function({int? retainAfterMs})?
  _compactUsage;
  final Future<List<AppSession>> Function() _loadSessions;
  final Future<List<TeamProfile>> Function() _loadTeams;
  final DateTime Function() _now;

  StreamSubscription<void>? _storageSub;
  StreamSubscription<UsageSyncProgress>? _syncProgressSub;
  UsageSyncHandle? _activeHandle;
  Future<void>? _loadFlight;
  Future<void>? _syncFlight;
  bool _syncManual = true;
  bool _syncFull = false;
  UsagePricingCatalog _pricing = const UsagePricingCatalog();
  List<SessionUsageEvent> _events = const [];
  late final UsageDashboardEngine _engine;
  final int isolateThreshold;
  int _computeGeneration = 0;
  UsageAttribution _attribution = const UsageAttribution();

  Future<void> ensureLoaded() {
    if (state.status == SessionUsageStatus.ready ||
        state.status == SessionUsageStatus.loading) {
      return _loadFlight ?? Future<void>.value();
    }
    return _startLoad(emitLoading: true);
  }

  Future<void> reload() => _startLoad(emitLoading: false);

  Future<void> _startLoad({required bool emitLoading}) {
    final inFlight = _loadFlight;
    if (inFlight != null) return inFlight;

    if (emitLoading) {
      emit(
        state.copyWith(status: SessionUsageStatus.loading, clearError: true),
      );
    }

    final future = _loadInternal();
    _loadFlight = future;
    return future.whenComplete(() {
      if (identical(_loadFlight, future)) _loadFlight = null;
    });
  }

  Future<void> _loadInternal() async {
    try {
      final events = await _loadEvents();
      final sessions = await _loadSessions();
      final teams = await _loadTeams();
      var pricingCorrupted = false;
      UsagePricingCatalog pricing;
      final loadPricing = _loadPricing;
      if (loadPricing == null) {
        pricing = UsagePricingCatalog.builtIn();
      } else {
        try {
          final loaded = await loadPricing();
          pricing = UsagePricingCatalog(userRules: loaded.rules);
          pricingCorrupted = loaded.corrupted;
        } on Object {
          pricing = UsagePricingCatalog.builtIn();
          pricingCorrupted = true;
        }
      }
      if (isClosed) return;
      _events = events;
      _pricing = pricing;
      _computeGeneration++;
      _engine.clearCache();
      _attribution = UsageAttribution.fromSessionsAndTeams(
        sessions: sessions,
        teams: teams,
      );
      final accounts =
          await (_loadCursorAccounts?.call() ??
              Future<List<CursorUsageAccount>>.value(const []));
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SessionUsageStatus.ready,
          dashboard: _computeDashboard(),
          pricing: pricing,
          pricingCorrupted: pricingCorrupted,
          cursorAccounts: accounts,
          clearError: true,
        ),
      );
      // Cursor rows come from the account caches; refresh them for the current
      // range in the background, then reload the events they produce.
      unawaited(_refreshCursorAccountUsage());    } catch (error, stackTrace) {
      AppLogger.instance.e(
        '[usage] load failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: state.hasData
              ? SessionUsageStatus.ready
              : SessionUsageStatus.error,
          errorMessage: '$error',
        ),
      );
    }
  }

  Future<void> sync({bool manual = true, bool full = false}) {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    _syncManual = manual;
    _syncFull = full;
    // The sync buttons cover Cursor accounts too: the transcript scan and the
    // account fetches run in sequence so one progress indicator covers both.
    final future = _syncInternal().then(
      (_) => _refreshCursorAccountUsage(full: full),
    );
    _syncFlight = future;
    return future.whenComplete(() {
      if (identical(_syncFlight, future)) _syncFlight = null;
    });
  }

  Future<void> syncIfStale({Duration ttl = const Duration(minutes: 5)}) {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    final last = state.lastSyncAtMs;
    if (last != null &&
        _now().millisecondsSinceEpoch - last < ttl.inMilliseconds) {
      return Future<void>.value();
    }
    return sync(manual: false);
  }

  Future<void> fullSync() => sync(manual: true, full: true);

  void cancelSync() {
    final handle = _activeHandle;
    if (handle == null || state.isCancelling) return;
    emit(state.copyWith(isCancelling: true));
    handle.cancel();
  }

  Future<UsageSyncResult> _runSync() async {
    final starter = _syncFull ? (_startFullSync ?? _startSync) : _startSync;
    if (starter == null) return _syncAll();

    final handle = starter();
    _activeHandle = handle;
    var lastProgressEmitMs = 0;
    _syncProgressSub = handle.progress.listen((progress) {
      if (isClosed || !state.isSyncing) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isFinal =
          progress.targetsTotal > 0 &&
          progress.targetsDone >= progress.targetsTotal;
      if (!isFinal && now - lastProgressEmitMs < 120) return;
      lastProgressEmitMs = now;
      if (state.syncProgress == progress) return;
      emit(state.copyWith(syncProgress: progress));
    });
    try {
      return await handle.done;
    } finally {
      final sub = _syncProgressSub;
      _syncProgressSub = null;
      _activeHandle = null;
      if (sub != null) unawaited(sub.cancel());
    }
  }

  Future<void> _syncInternal() async {
    if (isClosed) return;
    emit(
      state.copyWith(
        isSyncing: true,
        isCancelling: false,
        syncCancelled: false,
        clearSyncProgress: true,
        syncFailed: false,
        syncErrors: const [],
        clearError: true,
      ),
    );

    try {
      final result = await _runSync();
      final events = await _loadEvents();
      final sessions = await _loadSessions();
      final teams = await _loadTeams();
      if (isClosed) return;
      _events = events;
      _computeGeneration++;
      _engine.clearCache();
      _attribution = UsageAttribution.fromSessionsAndTeams(
        sessions: sessions,
        teams: teams,
      );
      emit(
        state.copyWith(
          status: SessionUsageStatus.ready,
          dashboard: _computeDashboard(),
          isSyncing: false,
          isCancelling: false,
          clearSyncProgress: true,
          lastSyncAtMs: _now().millisecondsSinceEpoch,
          lastSyncResult: result,
          syncErrors: result.errors,
          syncFailed: false,
          syncCancelled: result.cancelled,
          lastSyncManual: _syncManual,
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.instance.e(
        '[usage] sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          isSyncing: false,
          isCancelling: false,
          clearSyncProgress: true,
          syncFailed: true,
          syncCancelled: false,
          clearLastSyncResult: true,
        ),
      );
    }
  }

  void setRange(UsageRange range) {
    _updateFilter(range: range, clearCustomRange: true, liveEnd: false);
    unawaited(_refreshCursorAccountUsage());
  }

  /// True when Cursor account rows can change what the page shows.
  bool get _showsCursorRows => state.cli == null || state.cli == CliTool.cursor;

  /// Fetches Cursor account usage for the current range, then reloads the
  /// events so the dashboard picks the new rows up.
  ///
  /// Runs off the hot path: the page keeps showing cached numbers while the
  /// per-account caches fill in. Callers for the same range share one in-flight
  /// request; a full sync may interrupt an incremental one.
  Future<void> _refreshCursorAccountUsage({bool full = false}) {
    if (!_showsCursorRows) return Future<void>.value();
    final sync = _syncCursorUsage;
    if (sync == null) return Future<void>.value();
    final inFlight = _cursorSyncFlight;
    if (inFlight != null && !full) return inFlight;
    final future = _runCursorRefresh(sync, full: full);
    _cursorSyncFlight = future;
    return future.whenComplete(() {
      if (identical(_cursorSyncFlight, future)) _cursorSyncFlight = null;
    });
  }

  Future<void> _runCursorRefresh(
    Future<void> Function(UsageRange range, int? startMs, int? endMs, bool full)
    sync, {
    required bool full,
  }) async {
    final generation = ++_cursorSyncGeneration;
    try {
      await sync(state.range, state.customStartMs, state.customEndMs, full);
    } on Object {
      return;
    }
    if (isClosed || generation != _cursorSyncGeneration) return;
    try {
      final events = await _loadEvents();
      if (isClosed || generation != _cursorSyncGeneration) return;
      _events = events;
      _computeGeneration++;
      _engine.clearCache();
      emit(
        state.copyWith(
          dashboard: _computeDashboard(),
          isComputing: false,
        ),
      );
    } on Object {
      // Keep whatever the cache already produced.
    }
  }

  void setCustomRange({
    required int startMs,
    required int endMs,
    bool liveEnd = false,
  }) {
    _updateFilter(
      range: UsageRange.custom,
      customStartMs: startMs,
      customEndMs: endMs,
      liveEnd: liveEnd,
    );
    unawaited(_refreshCursorAccountUsage());
  }

  void refreshRangeNow() {
    if (!state.liveEnd) return;
    _updateFilter();
  }

  void setCli(CliTool? cli) {
    _updateFilter(cli: cli, clearCli: cli == null);
    // Switching into (or back out of) the Cursor filter can need its rows.
    unawaited(_refreshCursorAccountUsage());
  }

  /// Filters the dashboard to one Cursor account; null means all of them.
  void setCursorAccount(String? accountId) => _updateFilter(
    cursorAccountId: accountId,
    clearCursorAccount: accountId == null,
  );

  void setGroupBy(UsageGroupBy groupBy) => _updateFilter(groupBy: groupBy);

  void setQuery(String query) => _updateFilter(query: query);

  void resetFilters() {
    _updateFilter(
      range: UsageRange.all,
      cli: null,
      clearCli: true,
      groupBy: UsageGroupBy.session,
      query: '',
      clearCustomRange: true,
      liveEnd: false,
    );
  }

  void clearSyncErrors() {
    emit(state.copyWith(syncErrors: const [], syncFailed: false));
  }

  void clearLoadError() => emit(state.copyWith(clearError: true));

  Future<void> savePricing(List<UsagePriceRule> rules) async {
    final saver = _savePricing;
    if (saver == null || state.pricingSaving) return;

    emit(state.copyWith(pricingSaving: true, clearPricingError: true));
    try {
      await saver(rules);
      if (isClosed) return;
      _pricing = UsagePricingCatalog(userRules: rules);
      _engine.clearCache();
      emit(
        state.copyWith(
          pricing: _pricing,
          pricingSaving: false,
          pricingCorrupted: false,
          dashboard: _computeDashboard(),
          clearPricingError: true,
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(pricingSaving: false, pricingError: '$error'));
    }
  }

  Future<void> resetPricing() => savePricing(const []);

  Future<void> loadMaintenanceStats() async {
    final loader = _loadUsageStats;
    if (loader == null || state.maintenanceBusy) return;
    emit(state.copyWith(maintenanceBusy: true, clearMaintenanceError: true));
    try {
      final stats = await loader();
      if (isClosed) return;
      emit(state.copyWith(usageStats: stats, maintenanceBusy: false));
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(maintenanceBusy: false, maintenanceError: '$error'));
    }
  }

  Future<bool> compactUsage({int? retainAfterMs}) async {
    final compactor = _compactUsage;
    if (compactor == null || state.maintenanceBusy || state.isSyncing) {
      return false;
    }
    emit(state.copyWith(maintenanceBusy: true, clearMaintenanceError: true));
    try {
      await compactor(retainAfterMs: retainAfterMs);
      await reload();
      final stats = await _loadUsageStats?.call();
      if (isClosed) return false;
      emit(
        state.copyWith(
          usageStats: stats,
          maintenanceBusy: false,
          clearMaintenanceError: true,
        ),
      );
      return true;
    } on Object catch (error) {
      if (isClosed) return false;
      emit(state.copyWith(maintenanceBusy: false, maintenanceError: '$error'));
      return false;
    }
  }

  void _updateFilter({
    UsageRange? range,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
    int? customStartMs,
    int? customEndMs,
    bool clearCustomRange = false,
    bool? liveEnd,
    String? cursorAccountId,
    bool clearCursorAccount = false,
  }) {
    final next = state.copyWith(
      range: range,
      cli: cli,
      clearCli: clearCli,
      groupBy: groupBy,
      query: query,
      customStartMs: customStartMs,
      customEndMs: customEndMs,
      clearCustomRange: clearCustomRange,
      liveEnd: liveEnd,
      cursorAccountId: cursorAccountId,
      clearCursorAccount: clearCursorAccount,
    );
    final nowMs = _now().millisecondsSinceEpoch;
    final cached = _engine.cached(_filterFor(next), nowMs);
    if (cached != null) {
      _computeGeneration++;
      emit(next.copyWith(dashboard: cached, isComputing: false));
      return;
    }
    if (_events.length < _engine.isolateThreshold) {
      emit(
        next.copyWith(dashboard: _computeDashboard(next), isComputing: false),
      );
      return;
    }
    final generation = ++_computeGeneration;
    emit(next.copyWith(isComputing: true));
    unawaited(_computeDashboardInBackground(next, generation, nowMs));
  }

  UsageFilter _filterFor(SessionUsageState current) => UsageFilter(
    range: current.range,
    cli: current.cli,
    groupBy: current.groupBy,
    query: current.query,
    customStartMs: current.customStartMs,
    customEndMs: current.customEndMs,
    accountId: current.cursorAccountId,
    liveEnd: current.liveEnd,
  );

  Future<void> _computeDashboardInBackground(
    SessionUsageState current,
    int generation,
    int nowMs,
  ) async {
    UsageDashboard dashboard;
    try {
      dashboard = await _engine.dashboardForAsync(
        events: _events,
        attribution: _attribution,
        pricing: _pricing,
        filter: _filterFor(current),
        nowMs: nowMs,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[usage] background dashboard failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      dashboard = _computeDashboard(current);
    }
    if (isClosed || generation != _computeGeneration) return;
    emit(state.copyWith(dashboard: dashboard, isComputing: false));
  }

  UsageDashboard _computeDashboard([SessionUsageState? stateOverride]) {
    final current = stateOverride ?? state;
    return _engine.dashboardFor(
      events: _events,
      attribution: _attribution,
      pricing: _pricing,
      filter: _filterFor(current),
      nowMs: _now().millisecondsSinceEpoch,
    );
  }

  List<UsageHeatmapDay> _heatmapFor(CliTool? cli) =>
      _engine.heatmapFor(events: _events, pricing: _pricing, cli: cli);

  @override
  Future<void> close() async {
    _activeHandle?.cancel();
    _activeHandle = null;
    final progressSub = _syncProgressSub;
    _syncProgressSub = null;
    if (progressSub != null) unawaited(progressSub.cancel());
    await _storageSub?.cancel();
    _storageSub = null;
    return super.close();
  }
}
