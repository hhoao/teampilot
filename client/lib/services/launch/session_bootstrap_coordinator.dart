import 'dart:async';

import '../../utils/logging/logger.dart';

/// Result of session-level bootstrap provisioning — shared resources that must
/// be set up once per session before any member launches.
///
/// The bootstrap handles credential linking, workspace trust, and provider
/// settings resolution — operations that were previously called redundantly
/// from every member's per-member [contributeLaunch], producing unnecessary
/// manifest entries and risking filesystem races under concurrency.
class SessionBootstrapResult {
  const SessionBootstrapResult({
    this.warnings = const [],
  });

  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Ensures session-level shared resources are provisioned exactly once,
/// regardless of how many members launch concurrently.
///
/// Follows the same shared-future deduplication pattern as
/// [WorkspaceProvisionCoordinator]: the first caller starts the work, and all
/// concurrent callers — as well as any later deferred-materialize callers —
/// receive the same completed result without re-executing.
///
/// The [run] callback is provided per-call rather than at construction time so
/// that the caller can capture the session-specific context (workspace, team,
/// CLI, target, config-profile service) without threading it through the DI
/// chain.
class SessionBootstrapCoordinator {
  SessionBootstrapCoordinator();

  final _inFlight = <String, Future<SessionBootstrapResult>>{};
  final _done = <String, SessionBootstrapResult>{};

  /// Returns a cached result when the session has already been bootstrapped,
  /// awaits an in-flight bootstrap future, or starts a new bootstrap using
  /// [run].
  ///
  /// Safe to call concurrently — only one [run] future is ever in flight per
  /// [sessionId].
  Future<SessionBootstrapResult> ensureBootstrapped(
    String sessionId,
    Future<SessionBootstrapResult> Function() run,
  ) async {
    final cached = _done[sessionId];
    if (cached != null) return cached;

    final inFlight = _inFlight[sessionId];
    if (inFlight != null) return inFlight;

    final future = _start(sessionId, run);
    _inFlight[sessionId] = future;
    return future;
  }

  Future<SessionBootstrapResult> _start(
    String sessionId,
    Future<SessionBootstrapResult> Function() run,
  ) async {
    try {
      final result = await run();
      _done[sessionId] = result;
      return result;
    } on Object catch (e, st) {
      appLogger.w(
        '[session-bootstrap] bootstrap failed session=$sessionId: $e',
        error: e,
        stackTrace: st,
      );
      // Cache failures too so concurrent waiters don't retry forever.
      final failure = SessionBootstrapResult(warnings: ['$e']);
      _done[sessionId] = failure;
      return failure;
    } finally {
      _inFlight.remove(sessionId);
    }
  }
}
