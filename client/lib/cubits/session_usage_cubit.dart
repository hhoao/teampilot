import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/session_usage.dart';
import '../models/session_usage_dashboard.dart';
import '../models/team_config.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/usage_aggregator.dart';
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
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    Stream<void>? storageChanges,
    DateTime Function()? now,
  }) : _loadEvents = loadEvents,
       _syncAll = syncAll,
       _startSync = startSync,
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
  final Future<List<AppSession>> Function() _loadSessions;
  final Future<List<TeamProfile>> Function() _loadTeams;
  final DateTime Function() _now;

  StreamSubscription<void>? _storageSub;
  StreamSubscription<UsageSyncProgress>? _syncProgressSub;
  UsageSyncHandle? _activeHandle;
  Future<void>? _loadFlight;
  Future<void>? _syncFlight;
  bool _syncManual = true;
  List<SessionUsageEvent> _events = const [];
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

  Future<void> sync({bool manual = true}) {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    _syncManual = manual;
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

  void cancelSync() {
    final handle = _activeHandle;
    if (handle == null || state.isCancelling) return;
    emit(state.copyWith(isCancelling: true));
    handle.cancel();
  }

  Future<UsageSyncResult> _runSync() async {
    final starter = _startSync;
    if (starter == null) return _syncAll();

    final handle = starter();
    _activeHandle = handle;
    _syncProgressSub = handle.progress.listen((progress) {
      if (isClosed || !state.isSyncing) return;
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
    );
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
