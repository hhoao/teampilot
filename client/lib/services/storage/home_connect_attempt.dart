import 'dart:async';

import '../../models/ssh_profile.dart';
import '../ssh/ssh_connection_failure.dart';
import '../ssh/tcp_reachability_probe.dart';
import 'runtime_context.dart';

enum HomeErrorKind {
  tcpUnreachable,
  sshTimeout,
  authFailed,

  /// The host key / identity no longer matches the one this profile trusts.
  /// Needs a deliberate re-pair or key confirmation, not a retry.
  hostIdentityChanged,
  transportError,
  unknown,
}

/// Outcome of a bounded home connect attempt.
class HomeConnectResult {
  const HomeConnectResult.connected(RuntimeContext this.context)
    : reachable = true,
      errorKind = null;
  const HomeConnectResult.unreachable(
    HomeErrorKind this.errorKind, {
    this.context,
  }) : reachable = false;

  final bool reachable;
  final RuntimeContext? context;
  final HomeErrorKind? errorKind;
}

/// Runs a TCP probe and a time-bounded home resolve so an unreachable or slow
/// SSH host fails fast instead of hanging the splash screen.
class HomeConnectAttempt {
  HomeConnectAttempt({
    required TcpReachabilityProbe probe,
    required Future<RuntimeContext> Function() resolve,
    Future<RuntimeContext?> Function()? cacheContext,
    required SshProfile? Function(String profileId) profileById,
    this.tcpTimeout = const Duration(seconds: 2),
    this.connectBudget = const Duration(seconds: 8),
  }) : _probe = probe,
       _resolve = resolve,
       _cacheContext = cacheContext,
       _profileById = profileById;

  final TcpReachabilityProbe _probe;
  final Future<RuntimeContext> Function() _resolve;

  /// Builds a context from persisted `lastHome`/`lastAppDataRoot` without any
  /// network I/O, or `null` when nothing usable is cached yet. Optional so
  /// callers that lack cached paths can still report unreachable; such results
  /// then carry no [HomeConnectResult.context].
  final Future<RuntimeContext?> Function()? _cacheContext;
  final SshProfile? Function(String profileId) _profileById;
  final Duration tcpTimeout;
  final Duration connectBudget;

  Future<HomeConnectResult> run(String profileId) async {
    final profile = _profileById(profileId);
    if (profile == null) {
      return HomeConnectResult.unreachable(
        HomeErrorKind.unknown,
        context: await _cachedContext(),
      );
    }
    final tcpOk = await _probe.isReachable(
      profile.host,
      profile.port,
      timeout: tcpTimeout,
    );
    if (!tcpOk) {
      return HomeConnectResult.unreachable(
        HomeErrorKind.tcpUnreachable,
        context: await _cachedContext(),
      );
    }
    try {
      final ctx = await _resolve().timeout(connectBudget);
      if (ctx.pathsFromCache) {
        return HomeConnectResult.unreachable(
          HomeErrorKind.transportError,
          context: ctx,
        );
      }
      return HomeConnectResult.connected(ctx);
    } on TimeoutException {
      return HomeConnectResult.unreachable(
        HomeErrorKind.sshTimeout,
        context: await _cachedContext(),
      );
    } on Object catch (error) {
      return HomeConnectResult.unreachable(
        isSshHostKeyFailure(error)
            ? HomeErrorKind.hostIdentityChanged
            : isSshAuthFailure(error)
            ? HomeErrorKind.authFailed
            : HomeErrorKind.transportError,
        context: await _cachedContext(),
      );
    }
  }

  Future<RuntimeContext?> _cachedContext() async {
    final cacheContext = _cacheContext;
    if (cacheContext == null) return null;
    try {
      return await cacheContext();
    } on Object {
      return null;
    }
  }
}
