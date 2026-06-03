import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  });

  final String cliTeamName;
  final String? memberToolConfigDir;
  final Map<String, TerminalSession> memberShells;

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
    : _memberPresenceService =
          memberPresenceService ?? MemberPresenceService(),
      super(const MemberPresenceState());

  final MemberPresenceService _memberPresenceService;
  Timer? _presencePollTimer;
  TeamConfig? _presenceTeam;
  PresenceTarget? _target;
  int _presencePollGeneration = 0;
  bool _presenceUiAttached = false;
  bool _presenceTickInFlight = false;

  MemberPresence memberPresenceFor(String memberId) =>
      state.presence[memberId] ?? const MemberPresence.offline();

  /// Pushed by ChatCubit when the active tab / shells change.
  void updateTarget(PresenceTarget? target) {
    _target = target;
    _schedulePresencePollingRestart();
  }

  void attachPresenceUi() {
    if (_presenceUiAttached) return;
    _presenceUiAttached = true;
    _schedulePresencePollingRestart();
  }

  void detachPresenceUi() {
    if (!_presenceUiAttached) return;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void stopPresencePolling() {
    _presenceTeam = null;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void _invalidatePresencePolls() {
    _presencePollGeneration++;
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
  }

  void syncPresenceTeam(TeamConfig? team) {
    if (_samePresenceTeam(_presenceTeam, team)) return;
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

  static bool _samePresenceTeam(TeamConfig? a, TeamConfig? b) {
    if (a == null || b == null) return a == b;
    if (a.id != b.id || a.cli != b.cli) return false;
    if (a.members.length != b.members.length) return false;
    for (var i = 0; i < a.members.length; i++) {
      if (a.members[i].id != b.members[i].id) return false;
    }
    return true;
  }

  void _restartPresencePolling() {
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
    final team = _presenceTeam;
    if (team == null || team.members.isEmpty) {
      if (state.presence.isNotEmpty) _emitMemberPresence(const {});
      return;
    }
    if (!_shouldPollPresence()) {
      if (state.presence.isNotEmpty) _emitMemberPresence(const {});
      return;
    }
    final generation = _presencePollGeneration;
    _presencePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickMemberPresence(team, generation));
    });
    unawaited(_tickMemberPresence(team, generation));
  }

  Future<void> _tickMemberPresence(TeamConfig team, int generation) async {
    if (isClosed || generation != _presencePollGeneration) return;
    if (!_shouldPollPresence()) return;
    if (_presenceTickInFlight) return;
    final target = _target;
    if (target == null) return;

    _presenceTickInFlight = true;
    try {
      final next = await _memberPresenceService.compute(
        teamCli: team.cli,
        members: team.members,
        cliTeamName: target.cliTeamName,
        memberToolConfigDir: target.memberToolConfigDir,
        memberShells: target.memberShells,
      );
      if (isClosed ||
          generation != _presencePollGeneration ||
          !_shouldPollPresence()) {
        return;
      }
      _emitMemberPresence(next);
    } finally {
      _presenceTickInFlight = false;
    }
  }

  @override
  Future<void> close() async {
    _invalidatePresencePolls();
    await super.close();
  }
}
