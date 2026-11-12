import 'dart:async';

/// Per-profile state of the shared SSH transport's dial gate.
///
/// `idle` means "nothing known yet", so the first lazy caller may start the
/// dial. `connecting` lets concurrent callers join that dial. `up` is the only
/// state in which a lost transport may be dialed again by a normal caller.
/// `down` is the circuit-breaker state: I/O fails fast until
/// [SshProfileConnectionCoordinator] re-arms the profile. `suspended` is a
/// deliberate stop (user disconnect, non-retryable auth/host-key failure) that
/// only an explicit resume clears.
enum SshConnectionGateState { idle, connecting, up, down, suspended }

/// Thrown by [SshConnectionGate.beforeIo] when a profile is known unreachable.
///
/// Callers should treat this as "wait for the transport to come back", not as a
/// data error: it is not a failed read, it is a missing connection. It is
/// reported through [isSshProfileDown] so storage repos rethrow it instead of
/// treating it as empty data.
final class SshProfileDownException implements Exception {
  const SshProfileDownException(this.profileId, this.state);

  final String profileId;
  final SshConnectionGateState state;

  @override
  String toString() => 'SshProfileDownException($profileId, ${state.name})';
}

/// Whether [error] is the gate's "profile is down" signal.
bool isSshProfileDown(Object? error) => error is SshProfileDownException;

/// Tracks one shared SSH transport per profile and decides who may dial it.
///
/// The gate is deliberately *not* a retry loop. It only records state and
/// rejects I/O while a profile is known-down. Exactly one driver — the
/// [SshProfileConnectionCoordinator] — may call [allowNextDial] to bypass the
/// breaker; every other caller goes through [beforeIo]. This keeps one failed
/// home connection from turning into one dial per consumer per retry.
final class SshConnectionGate {
  /// Notified when a consumer starts waiting in [waitUntilUp]. The coordinator
  /// uses this as the demand signal to keep (or restart) its retry loop.
  void Function(String profileId)? onWaiter;

  /// Notified on the transition into `down`. The coordinator starts its retry
  /// loop from this, so a failed lazy dial cannot leave the profile stuck down.
  void Function(String profileId)? onDown;

  final Map<String, _SshConnectionGateEntry> _entries = {};

  SshConnectionGateState stateOf(String profileId) =>
      _entries[profileId]?.state ?? SshConnectionGateState.idle;

  bool isUp(String profileId) =>
      stateOf(profileId) == SshConnectionGateState.up;

  bool isDown(String profileId) {
    final state = stateOf(profileId);
    return state == SshConnectionGateState.down ||
        state == SshConnectionGateState.suspended;
  }

  bool isSuspended(String profileId) =>
      stateOf(profileId) == SshConnectionGateState.suspended;

  bool hasWaiters(String profileId) => _entries[profileId]?.hasWaiters ?? false;

  /// Normal I/O entry point. Returns when a dial is allowed; throws
  /// [SshProfileDownException] when it is not.
  void beforeIo(String profileId) {
    final entry = _entry(profileId);
    switch (entry.state) {
      case SshConnectionGateState.idle:
      case SshConnectionGateState.up:
      case SshConnectionGateState.connecting:
        return;
      case SshConnectionGateState.down:
      case SshConnectionGateState.suspended:
        throw SshProfileDownException(profileId, entry.state);
    }
  }

  /// Coordinator-only bypass: let the single retry driver dial even while the
  /// profile is down. A suspension is never bypassed.
  void allowNextDial(String profileId) {
    final entry = _entry(profileId);
    if (entry.state == SshConnectionGateState.suspended) return;
    entry.state = SshConnectionGateState.connecting;
  }

  void markConnecting(String profileId) {
    final entry = _entry(profileId);
    if (entry.state == SshConnectionGateState.suspended) return;
    entry.state = SshConnectionGateState.connecting;
  }

  void markUp(String profileId) {
    final entry = _entry(profileId);
    if (entry.state == SshConnectionGateState.suspended) return;
    entry.state = SshConnectionGateState.up;
    entry.completeWaiters();
  }

  void markDown(String profileId) {
    final entry = _entry(profileId);
    if (entry.state == SshConnectionGateState.suspended) return;
    final wasDown = entry.state == SshConnectionGateState.down;
    entry.state = SshConnectionGateState.down;
    // Existing waiters stay parked: the next `markUp` recovers them.
    if (!wasDown) onDown?.call(profileId);
  }

  /// Stops every dial until [resume]. Used for user disconnect and permanent
  /// (host-key / auth) failures.
  void suspend(String profileId) {
    final entry = _entry(profileId);
    entry.state = SshConnectionGateState.suspended;
    entry.failWaiters(
      SshProfileDownException(profileId, SshConnectionGateState.suspended),
    );
  }

  /// Clears a suspension after an explicit user retry / profile edit.
  void resume(String profileId) {
    final entry = _entry(profileId);
    if (entry.state != SshConnectionGateState.suspended) return;
    entry.state = SshConnectionGateState.idle;
  }

  /// Completes when [profileId] is up again. The waiter is a demand signal for
  /// the coordinator: it keeps retrying (or restarts the loop) while waiters
  /// exist.
  Future<void> waitUntilUp(String profileId, {Duration? timeout}) {
    if (isUp(profileId)) return Future<void>.value();
    if (isSuspended(profileId)) {
      return Future<void>.error(
        SshProfileDownException(profileId, SshConnectionGateState.suspended),
      );
    }
    final entry = _entry(profileId);
    final waiter = entry.addWaiter();
    onWaiter?.call(profileId);
    if (timeout == null) return waiter.future;
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        entry.removeWaiter(waiter);
        throw TimeoutException(
          'SSH profile $profileId did not become available',
          timeout,
        );
      },
    );
  }

  void dispose() {
    onWaiter = null;
    onDown = null;
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }

  _SshConnectionGateEntry _entry(String profileId) =>
      _entries.putIfAbsent(profileId, _SshConnectionGateEntry.new);
}

final class _SshConnectionGateEntry {
  SshConnectionGateState state = SshConnectionGateState.idle;

  final List<Completer<void>> _waiters = [];

  bool get hasWaiters => _waiters.isNotEmpty;

  Completer<void> addWaiter() {
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter;
  }

  void removeWaiter(Completer<void> waiter) {
    _waiters.remove(waiter);
  }

  void completeWaiters() {
    if (_waiters.isEmpty) return;
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void failWaiters(Object error) {
    if (_waiters.isEmpty) return;
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  void dispose() {
    failWaiters(StateError('SSH connection gate disposed'));
  }
}
