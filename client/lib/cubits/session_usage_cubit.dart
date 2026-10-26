import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/session_usage.dart';
import '../models/session_usage_dashboard.dart';
import '../models/team_config.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/usage_aggregator.dart';
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
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    Stream<void>? storageChanges,
    DateTime Function()? now,
  }) : _loadEvents = loadEvents,
       _syncAll = syncAll,
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
  final Future<List<AppSession>> Function() _loadSessions;
  final Future<List<TeamProfile>> Function() _loadTeams;
  final DateTime Function() _now;

  StreamSubscription<void>? _storageSub;
  Future<void>? _loadFlight;
  Future<void>? _syncFlight;
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

  Future<void> sync() {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    final future = _syncInternal();
    _syncFlight = future;
    return future.whenComplete(() {
      if (identical(_syncFlight, future)) _syncFlight = null;
    });
  }

  Future<void> _syncInternal() async {
    emit(
      state.copyWith(
        isSyncing: true,
        syncFailed: false,
        syncErrors: const [],
        clearError: true,
      ),
    );

    try {
      final result = await _syncAll();
      final events = await _loadEvents();
      final sessions = await _loadSessions();
      final teams = await _loadTeams();
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
          lastSyncAtMs: _now().millisecondsSinceEpoch,
          lastSyncResult: result,
          syncErrors: result.errors,
          syncFailed: false,
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.instance.e(
        '[usage] sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          isSyncing: false,
          syncFailed: true,
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
    await _storageSub?.cancel();
    _storageSub = null;
    return super.close();
  }
}
