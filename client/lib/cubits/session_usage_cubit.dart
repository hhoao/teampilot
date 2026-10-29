import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/cursor_usage_import.dart';
import '../models/session_usage.dart';
import '../models/session_usage_dashboard.dart';
import '../models/session_usage_pricing.dart';
import '../models/team_config.dart';
import '../services/usage/cursor_usage_sync_service.dart';
import '../services/usage/session_usage_sync_service.dart';
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
    this.cli,
    this.groupBy = UsageGroupBy.session,
    this.query = '',
    this.isSyncing = false,
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
    this.cursorStatus = const CursorUsageImportStatus(),
    this.cursorBusy = false,
    this.cursorError,
    this.errorMessage,
  }) : syncErrors = List.unmodifiable(syncErrors);

  final SessionUsageStatus status;
  final UsageDashboard dashboard;
  final UsageRange range;
  final CliTool? cli;
  final UsageGroupBy groupBy;
  final String query;
  final bool isSyncing;
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
  final CursorUsageImportStatus cursorStatus;
  final bool cursorBusy;
  final CursorUsageSyncError? cursorError;
  final String? errorMessage;

  bool get hasData => dashboard.totalEventCount > 0;
  bool get hasSyncProblem => syncErrors.isNotEmpty || syncFailed;

  SessionUsageState copyWith({
    SessionUsageStatus? status,
    UsageDashboard? dashboard,
    UsageRange? range,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
    bool? isSyncing,
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
    CursorUsageImportStatus? cursorStatus,
    bool? cursorBusy,
    CursorUsageSyncError? cursorError,
    bool clearCursorError = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SessionUsageState(
      status: status ?? this.status,
      dashboard: dashboard ?? this.dashboard,
      range: range ?? this.range,
      cli: clearCli ? null : (cli ?? this.cli),
      groupBy: groupBy ?? this.groupBy,
      query: query ?? this.query,
      isSyncing: isSyncing ?? this.isSyncing,
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
      cursorStatus: cursorStatus ?? this.cursorStatus,
      cursorBusy: cursorBusy ?? this.cursorBusy,
      cursorError: clearCursorError ? null : (cursorError ?? this.cursorError),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    dashboard,
    range,
    cli,
    groupBy,
    query,
    isSyncing,
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
    cursorStatus,
    cursorBusy,
    cursorError,
    errorMessage,
  ];
}

/// Cached-event loader + manual sync state for the usage page.
///
/// The cubit never scans CLI transcripts itself; [syncAll] does that and the
/// cubit reloads the JSONL cache afterwards. Filters only recompute in memory.
final class SessionUsageCubit extends Cubit<SessionUsageState> {
  SessionUsageCubit({
    required Future<List<SessionUsageEvent>> Function() loadEvents,
    required Future<UsageSyncResult> Function() syncAll,
    UsageSyncHandle Function()? startSync,
    UsageSyncHandle Function()? startFullSync,
    Future<UsagePricingLoad> Function()? loadPricing,
    Future<void> Function(List<UsagePriceRule> rules)? savePricing,
    Future<UsageStoreStats> Function()? loadUsageStats,
    Future<UsageCompactResult> Function({int? retainAfterMs})? compactUsage,
    Future<CursorUsageImportStatus> Function()? loadCursorStatus,
    Future<CursorUsageImportResult> Function(String text)? importCursorCsv,
    Future<CursorUsageImportResult> Function()? syncCursorUsage,
    Future<void> Function()? clearCursorUsage,
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    Stream<void>? storageChanges,
    DateTime Function()? now,
  }) : _loadEvents = loadEvents,
       _syncAll = syncAll,
       _startSync = startSync,
       _startFullSync = startFullSync,
       _loadPricing = loadPricing,
       _savePricing = savePricing,
       _loadUsageStats = loadUsageStats,
       _compactUsage = compactUsage,
       _loadCursorStatus = loadCursorStatus,
       _importCursorCsv = importCursorCsv,
       _syncCursorUsage = syncCursorUsage,
       _clearCursorUsage = clearCursorUsage,
       _loadSessions = loadSessions,
       _loadTeams = loadTeams,
       _now = now ?? DateTime.now,
       super(SessionUsageState()) {
    _storageSub = storageChanges?.listen((_) {
      unawaited(reload());
    });
  }

  final Future<List<SessionUsageEvent>> Function() _loadEvents;
  final Future<UsageSyncResult> Function() _syncAll;
  final UsageSyncHandle Function()? _startSync;
  final UsageSyncHandle Function()? _startFullSync;
  final Future<UsagePricingLoad> Function()? _loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules)? _savePricing;
  final Future<UsageStoreStats> Function()? _loadUsageStats;
  final Future<UsageCompactResult> Function({int? retainAfterMs})?
  _compactUsage;
  final Future<CursorUsageImportStatus> Function()? _loadCursorStatus;
  final Future<CursorUsageImportResult> Function(String text)? _importCursorCsv;
  final Future<CursorUsageImportResult> Function()? _syncCursorUsage;
  final Future<void> Function()? _clearCursorUsage;
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
  List<UsageHeatmapDay>? _heatmapCache;
  List<SessionUsageEvent>? _heatmapCacheEvents;
  CliTool? _heatmapCacheCli;
  UsagePricingCatalog? _heatmapCachePricing;
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
      _attribution = UsageAttribution.fromSessionsAndTeams(
        sessions: sessions,
        teams: teams,
      );
      emit(
        state.copyWith(
          status: SessionUsageStatus.ready,
          dashboard: _computeDashboard(),
          pricing: pricing,
          pricingCorrupted: pricingCorrupted,
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
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
    final future = _syncInternal();
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

  void setRange(UsageRange range) => _updateFilter(range: range);

  void setCli(CliTool? cli) => _updateFilter(cli: cli, clearCli: cli == null);

  void setGroupBy(UsageGroupBy groupBy) => _updateFilter(groupBy: groupBy);

  void setQuery(String query) => _updateFilter(query: query);

  void resetFilters() {
    _updateFilter(
      range: UsageRange.all,
      cli: null,
      clearCli: true,
      groupBy: UsageGroupBy.session,
      query: '',
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
  }) {
    final next = state.copyWith(
      range: range,
      cli: cli,
      clearCli: clearCli,
      groupBy: groupBy,
      query: query,
    );
    emit(next.copyWith(dashboard: _computeDashboard(next)));
  }

  UsageDashboard _computeDashboard([SessionUsageState? stateOverride]) {
    final current = stateOverride ?? state;
    return buildUsageDashboard(
      events: _events,
      attribution: _attribution,
      filter: UsageFilter(
        range: current.range,
        cli: current.cli,
        groupBy: current.groupBy,
        query: current.query,
      ),
      nowMs: _now().millisecondsSinceEpoch,
      pricing: _pricing,
      heatmap: _heatmapFor(current.cli),
    );
  }

  List<UsageHeatmapDay> _heatmapFor(CliTool? cli) {
    final cached = _heatmapCache;
    if (cached != null &&
        identical(_heatmapCacheEvents, _events) &&
        _heatmapCacheCli == cli &&
        identical(_heatmapCachePricing, _pricing)) {
      return cached;
    }
    final next = buildUsageHeatmap(
      events: _events,
      cli: cli,
      pricing: _pricing,
    );
    _heatmapCache = next;
    _heatmapCacheEvents = _events;
    _heatmapCacheCli = cli;
    _heatmapCachePricing = _pricing;
    return next;
  }

  Future<void> loadCursorStatus() async {
    final loader = _loadCursorStatus;
    if (loader == null) return;
    try {
      final status = await loader();
      emit(state.copyWith(cursorStatus: status, clearCursorError: true));
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[usage] cursor status load failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<CursorUsageImportResult?> importCursorCsv(String text) =>
      _runCursorAction(() async {
        final action = _importCursorCsv;
        if (action == null) return null;
        return action(text);
      });

  Future<CursorUsageImportResult?> syncCursorUsage() =>
      _runCursorAction(() async {
        final action = _syncCursorUsage;
        if (action == null) return null;
        return action();
      });

  Future<bool> clearCursorUsage() async {
    final action = _clearCursorUsage;
    if (action == null) return false;
    emit(state.copyWith(cursorBusy: true, clearCursorError: true));
    try {
      await action();
      await loadCursorStatus();
      await _reloadAfterExternalWrite();
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[usage] clear cursor usage failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      emit(state.copyWith(cursorError: CursorUsageSyncError.http));
      return false;
    } finally {
      emit(state.copyWith(cursorBusy: false));
    }
  }

  Future<CursorUsageImportResult?> _runCursorAction(
    Future<CursorUsageImportResult?> Function() action,
  ) async {
    emit(state.copyWith(cursorBusy: true, clearCursorError: true));
    try {
      final result = await action();
      if (result == null) return null;
      emit(state.copyWith(cursorStatus: result.status));
      await _reloadAfterExternalWrite();
      return result;
    } on CursorUsageSyncException catch (error) {
      emit(state.copyWith(cursorError: error.code));
      return null;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[usage] cursor import failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      emit(state.copyWith(cursorError: CursorUsageSyncError.http));
      return null;
    } finally {
      emit(state.copyWith(cursorBusy: false));
    }
  }

  Future<void> _reloadAfterExternalWrite() async {
    final inFlight = _loadFlight;
    if (inFlight != null) await inFlight;
    await reload();
  }

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
