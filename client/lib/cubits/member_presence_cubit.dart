import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../utils/logging/logger.dart';
import '../services/event/agent_presence_event.dart';
import '../services/event/agent_presence_projection.dart';
import '../services/event/presence_event_bridge.dart';
import '../services/team/runtime_roster_cache.dart';
import '../models/app_session.dart';
import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../services/team/member_presence_service.dart';
import '../services/storage/home_storage.dart';
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
  const MemberPresenceState({
    this.presence = const {},
    this.occupiedSessionIds = const {},
  });

  final Map<String, MemberPresence> presence;
  final Set<String> occupiedSessionIds;

  MemberPresenceState copyWith({
    Map<String, MemberPresence>? presence,
    Set<String>? occupiedSessionIds,
  }) => MemberPresenceState(
    presence: presence ?? this.presence,
    occupiedSessionIds: occupiedSessionIds ?? this.occupiedSessionIds,
  );

  @override
  List<Object?> get props => [presence, occupiedSessionIds];
}

class MemberPresenceCubit extends Cubit<MemberPresenceState> {
  MemberPresenceCubit({
    required HomeStorage storage,
    MemberPresenceService? memberPresenceService,
    AgentPresenceProjection? presenceProjection,
    PresenceEventBridge? presenceBridge,
    void Function()? onProjectionChanged,
  }) : _memberPresenceService =
           memberPresenceService ?? MemberPresenceService(storage: storage),
       _presenceProjection = presenceProjection,
       _presenceBridge = presenceBridge,
       _onProjectionChanged = onProjectionChanged,
       super(const MemberPresenceState()) {
    _presenceChanges = presenceProjection?.changes.listen(
      _onProjectionSeatChanged,
    );
  }

  final MemberPresenceService _memberPresenceService;

  /// Pushed-events consumer edge: the authoritative availability per seat,
  /// reduced from [PresenceEventBridge] publishes by the shell's dispatcher.
  /// Null keeps the poll-derived behaviour (no events path wired).
  final AgentPresenceProjection? _presenceProjection;

  /// Pushed-events producer edge: dedupes the availability recomputed every
  /// tick into events. Null means no publishing.
  final PresenceEventBridge? _presenceBridge;

  /// Observable spy for tests; called before a projection change triggers a
  /// recompute.
  final void Function()? _onProjectionChanged;

  StreamSubscription<PresenceSeatKey>? _presenceChanges;

  /// Seats seen through the events path, dropped from the projection on close
  /// so it cannot grow unbounded.
  final Set<PresenceSeatKey> _knownSeats = <PresenceSeatKey>{};

  /// True when any part of the pushed-events path is wired. Without it the
  /// cubit stays exactly on the legacy poll-derived path.
  bool get _presenceEventsWired =>
      _presenceProjection != null || _presenceBridge != null;

  /// Stable tear-off handed to [TerminalSession.onPresenceInputsChanged] so the
  /// detach pass can recognise (and only clear) our own callback.
  late final void Function() _presencePushTrigger = _requestPresenceRecompute;

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
    _detachPresencePushTriggers(_target);
    _target = target;
    _attachPresencePushTriggers(target);
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
    _detachPresencePushTriggers(_target);
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
    _attachPresencePushTriggers(_target);
    final generation = _presencePollGeneration;
    unawaited(_tickMemberPresence(generation));
  }

  /// Reused by the per-seat push trigger and the projection's `changes`
  /// subscription. The in-flight guard in [_tickMemberPresence] coalesces a
  /// burst into one recompute.
  void _requestPresenceRecompute() {
    if (isClosed) return;
    unawaited(tickFromIdleWatch());
  }

  void _onProjectionSeatChanged(PresenceSeatKey seat) {
    _onProjectionChanged?.call();
    final occupied = _presenceProjection?.occupiedSessionIds ?? const <String>{};
    if (!setEquals(state.occupiedSessionIds, occupied)) {
      emit(state.copyWith(occupiedSessionIds: occupied));
    }
    _requestPresenceRecompute();
  }

  /// Points each target session's presence push at the recompute request so a
  /// turn latch / boot flip refreshes presence without waiting for the poll.
  void _attachPresencePushTriggers(PresenceTarget? target) {
    if (!_presenceEventsWired) return;
    final shells = target?.memberShells;
    if (shells == null) return;
    for (final shell in shells.values) {
      shell.onPresenceInputsChanged = _presencePushTrigger;
    }
  }

  /// Clears only triggers this cubit installed, so a session is never left
  /// calling into a cubit whose target is gone.
  void _detachPresencePushTriggers(PresenceTarget? target) {
    final shells = target?.memberShells;
    if (shells == null) return;
    for (final shell in shells.values) {
      if (identical(shell.onPresenceInputsChanged, _presencePushTrigger)) {
        shell.onPresenceInputsChanged = null;
      }
    }
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
      final computed = await _memberPresenceService.compute(
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
      final next = _applyPresenceEvents(computed, target);
      _logPresenceChanges(state.presence, next);
      _emitMemberPresence(_mergePreservingInstances(next));
    } finally {
      _presenceTickInFlight = false;
    }
  }

  /// Overlays the pushed-events availability onto the poll snapshot and reports
  /// each seat's freshly computed availability to [PresenceEventBridge].
  ///
  /// With no events path wired this returns [computed] unchanged. With a
  /// projection wired, the projected kind wins for the emitted availability
  /// (only while connected — connection is always poll-derived); the freshly
  /// computed value is what feeds the bridge, keeping the publish edge on the
  /// authoritative rule so the projection cannot freeze on its first value.
  ///
  /// One-hop latency: the production sink (`DispatcherAgentPresenceSink`) only
  /// *enqueues* on the dispatcher, so the projection observes a publish on a
  /// later turn of the consume loop. A tick that detects an availability change
  /// therefore still reads the *previous* projected value and emits it for that
  /// one hop; the projection's `changes` listener then requests the recompute
  /// that emits the fresh value. This is bounded latency, not a stuck
  /// one-hop-behind state — a recompute is only dropped while another tick is
  /// mid-flight (`_presenceTickInFlight`), and that in-flight tick re-reads the
  /// already-updated projection after its `await`.
  Map<String, MemberPresence> _applyPresenceEvents(
    Map<String, MemberPresence> computed,
    PresenceTarget target,
  ) {
    final projection = _presenceProjection;
    final bridge = _presenceBridge;
    if (projection == null && bridge == null) return computed;

    final out = <String, MemberPresence>{};
    for (final entry in computed.entries) {
      final presence = entry.value;
      final seat = target.memberShells[entry.key]?.presenceSeat;
      final connected = presence.connection == MemberConnection.connected;
      if (seat == null) {
        out[entry.key] = presence;
        continue;
      }
      _knownSeats.add(seat);
      bridge?.reportAvailability(
        seat,
        connected ? _kindFromAvailability(presence.availability) : null,
      );
      final projected = connected
          ? _availabilityFromKind(projection?.availabilityFor(seat))
          : null;
      out[entry.key] = projected == null
          ? presence
          : MemberPresence(
              connection: presence.connection,
              availability: projected,
            );
    }
    return out;
  }

  static AgentPresenceKind? _kindFromAvailability(
    MemberAvailability? availability,
  ) => switch (availability) {
    MemberAvailability.booting => AgentPresenceKind.booting,
    MemberAvailability.working => AgentPresenceKind.working,
    MemberAvailability.idle => AgentPresenceKind.idle,
    null => null,
  };

  static MemberAvailability? _availabilityFromKind(AgentPresenceKind? kind) =>
      switch (kind) {
        AgentPresenceKind.booting => MemberAvailability.booting,
        AgentPresenceKind.working => MemberAvailability.working,
        AgentPresenceKind.idle => MemberAvailability.idle,
        AgentPresenceKind.cleared => null,
        null => null,
      };

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
    _detachPresencePushTriggers(_target);
    final changes = _presenceChanges;
    _presenceChanges = null;
    // Tear the events edges down synchronously so no callback can re-enter a
    // closing cubit; only the cancellation future is awaited.
    final projection = _presenceProjection;
    if (projection != null) {
      for (final seat in _knownSeats) {
        projection.removeSeat(seat);
      }
    }
    _knownSeats.clear();
    _presenceBridge?.dispose();
    await changes?.cancel();
    if (!setEquals(state.occupiedSessionIds, const {})) {
      emit(state.copyWith(occupiedSessionIds: const {}));
    }
    await super.close();
  }
}
