import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../utils/logging/logger.dart';
import '../services/team/runtime_roster_cache.dart';
import '../models/app_session.dart';
import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../services/team/member_presence_service.dart';
import '../services/terminal/terminal_session.dart';

/// Snapshot of the active tab the presence poller needs. Pushed by ChatCubit
/// whenever the active tab / its shells change. Decouples presence from tabs.
class PresenceTarget {
  const PresenceTarget({
    required this.cliTeamName,
    required this.memberToolConfigDir,
    required this.memberShells,
    this.session,
  });

  final String cliTeamName;
  final String? memberToolConfigDir;
  final Map<String, TerminalSession> memberShells;

  /// Team + bus context for [MemberPresenceService.compute]. Null for tabs
  /// without a team session (personal / local-only).
  final PresenceSessionContext? session;

  bool get eligible =>
      memberShells.isNotEmpty ||
      (memberToolConfigDir?.trim().isNotEmpty ?? false);
}

class MemberPresenceState extends Equatable {
  const MemberPresenceState({this.presence = const {}});

  final Map<String, MemberPresence> presence;

  MemberPresenceState copyWith({Map<String, MemberPresence>? presence}) =>
      MemberPresenceState(presence: presence ?? this.presence);

  @override
  List<Object?> get props => [presence];
}

class MemberPresenceCubit extends Cubit<MemberPresenceState> {
  MemberPresenceCubit({MemberPresenceService? memberPresenceService})
    : _memberPresenceService = memberPresenceService ?? MemberPresenceService(),
      super(const MemberPresenceState());

  final MemberPresenceService _memberPresenceService;
  final RuntimeRosterCache _runtimeRosterCache = RuntimeRosterCache();
  TeamProfile? _presenceTeam;
  PresenceTarget? _target;
  int _presencePollGeneration = 0;

  /// Per-owner UI attachment tokens (one [RightToolsPanel] per workspace page).
  /// Refcounted instead of a single bool: during a workspace switch Flutter
  /// inflates the new page's panel (attach) BEFORE finalizeTree disposes the
  /// old page's panel (detach). A bool would let that late detach clobber the
  /// new attach, stopping polling and emitting empty presence — every member
  /// stuck at "offline". Staying attached while ANY owner remains avoids that.
  final Set<Object> _presenceUiOwners = <Object>{};
  late final Object _defaultUiOwner = Object();
  bool get _presenceUiAttached => _presenceUiOwners.isNotEmpty;
  bool _presenceTickInFlight = false;

  MemberPresence memberPresenceFor(String memberId) =>
      state.presence[memberId] ?? const MemberPresence.offline();

  /// Pushed by ChatCubit when the active tab / shells change.
  void updateTarget(PresenceTarget? target) {
    _target = target;
    _schedulePresencePollingRestart();
  }

  /// [owner] identifies the attaching UI (pass the [State] of each
  /// [RightToolsPanel]). Omit it for single-owner callers/tests.
  void attachPresenceUi([Object? owner]) {
    final wasAttached = _presenceUiAttached;
    if (!_presenceUiOwners.add(owner ?? _defaultUiOwner)) return;
    if (!wasAttached) _schedulePresencePollingRestart();
  }

  void detachPresenceUi([Object? owner]) {
    if (!_presenceUiOwners.remove(owner ?? _defaultUiOwner)) return;
    // Another panel (e.g. the next workspace page) is still attached — keep
    // polling and keep the current presence rather than clearing it.
    if (_presenceUiAttached) return;
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void stopPresencePolling() {
    _presenceTeam = null;
    _runtimeRosterCache.clear();
    _presenceUiOwners.clear();
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void _invalidatePresencePolls() {
    _presencePollGeneration++;
  }

  /// Called each second from [TabSessionRuntimeCoordinator] idle watch (via ChatCubit).
  Future<void> tickFromIdleWatch() async {
    await _tickMemberPresence(_presencePollGeneration);
  }

  void syncPresenceTeam(TeamProfile? team) {
    if (identical(_presenceTeam, team)) return;
    if (_presenceTeam != null && team != null && _presenceTeam == team) return;
    _runtimeRosterCache.clear();
    _presenceTeam = team;
    _schedulePresencePollingRestart();
  }

  void refreshPresencePolling() => _schedulePresencePollingRestart();

  void _schedulePresencePollingRestart() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      _restartPresencePolling();
    });
  }

  void _emitMemberPresence(Map<String, MemberPresence> next) {
    if (isClosed || mapEquals(next, state.presence)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed || mapEquals(next, state.presence)) return;
      emit(state.copyWith(presence: next));
    });
  }

  bool _shouldPollPresence() {
    if (!_presenceUiAttached || _presenceTeam == null) return false;
    final target = _target;
    if (target == null) return false;
    return target.eligible;
  }

  void _restartPresencePolling() {
    if (!_shouldPollPresence()) return;
    final generation = _presencePollGeneration;
    unawaited(_tickMemberPresence(generation));
  }

  Future<void> _tickMemberPresence(int generation) async {
    if (isClosed || generation != _presencePollGeneration) return;
    if (!_shouldPollPresence()) return;
    if (_presenceTickInFlight) return;
    final target = _target;
    if (target == null) return;

    final rosterTeam = _presenceTeam;
    if (rosterTeam == null || rosterTeam.members.isEmpty) return;

    _presenceTickInFlight = true;
    try {
      final appSession = target.session?.appSession;
      final members = appSession != null && appSession.members.isNotEmpty
          ? sessionRosterMembers(appSession, rosterTeam)
          : _runtimeRosterCache.resolve(rosterTeam);
      final next = await _memberPresenceService.compute(
        teamCli: rosterTeam.cli,
        members: members,
        cliTeamName: target.cliTeamName,
        memberToolConfigDir: target.memberToolConfigDir,
        memberShells: target.memberShells,
        session: target.session,
      );
      if (isClosed ||
          generation != _presencePollGeneration ||
          !_shouldPollPresence()) {
        return;
      }
      _logPresenceChanges(state.presence, next);
      _emitMemberPresence(_mergePreservingInstances(next));
    } finally {
      _presenceTickInFlight = false;
    }
  }

  void _logPresenceChanges(
    Map<String, MemberPresence> prev,
    Map<String, MemberPresence> next,
  ) {
    for (final entry in next.entries) {
      final old = prev[entry.key];
      if (old == entry.value) continue;
      final p = entry.value;
      appLogger.d(
        '[presence] ${entry.key} '
        'conn=${p.connection.name} '
        'avail=${p.availability?.name ?? 'null'}',
      );
    }
  }

  /// Reuses prior [MemberPresence] instances when values are unchanged so idle
  /// polls do not allocate or emit.
  Map<String, MemberPresence> _mergePreservingInstances(
    Map<String, MemberPresence> next,
  ) {
    final prev = state.presence;
    if (prev.isEmpty) return next;
    if (mapEquals(next, prev)) return prev;

    final out = <String, MemberPresence>{};
    for (final entry in next.entries) {
      final old = prev[entry.key];
      out[entry.key] = (old != null && old == entry.value) ? old : entry.value;
    }
    return mapEquals(out, prev) ? prev : out;
  }

  @override
  Future<void> close() async {
    _invalidatePresencePolls();
    await super.close();
  }
}
