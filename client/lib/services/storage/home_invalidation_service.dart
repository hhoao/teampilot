import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cubits/ssh_profile_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import 'home_storage.dart';
import 'home_ssh_profile_impact.dart';
import '../../utils/logging/logger.dart';

/// How much of the app-data boot chain an invalidation must rerun.
enum ReloadLevel {
  /// Unrelated churn — nothing to reload.
  none,

  /// Minor invalidation — rerun [AppDataBootstrap.bootstrapHomeIndex] only.
  ///
  /// Cubit loads are single-flight and already warm, so the auxiliary data
  /// chain (providers, skills, plugins, MCP, extensions) and workspace data
  /// reload are skipped.
  indexOnly,

  /// Storage-plane-affecting invalidation — rerun the entire reload chain.
  full,
}

/// Bootstrap-owned storage-plane invalidation: routes SSH catalog diffs and
/// [HomeStorage] plane swaps into level-based app-data reloads.
///
/// Replaces the `HomeSshProfileBinder` widget: invalidation lifecycle no
/// longer hangs off widget-tree mount state — a service never silently drops
/// a pending invalidation (no `mounted` checks). Subscribes to the profile
/// cubit's state stream (no widget, no `context.read`).
class HomeInvalidationService {
  HomeInvalidationService({
    required Stream<SshProfileState> profileStates,
    required Stream<StoragePlaneChange> storageChanges,
    required String Function() homeTargetId,
    required Future<void> Function(ReloadLevel level) reload,
    required Future<void> Function(String id) switchHome,
    List<SshProfile> initialProfiles = const [],
    this.fallbackHomeId = RuntimeTarget.localId,
  }) : _profileStates = profileStates,
       _storageChanges = storageChanges,
       _homeTargetId = homeTargetId,
       _reload = reload,
       _switchHome = switchHome,
       _lastProfiles = List<SshProfile>.of(initialProfiles);

  final Stream<SshProfileState> _profileStates;
  final Stream<StoragePlaneChange> _storageChanges;
  final String Function() _homeTargetId;
  final Future<void> Function(ReloadLevel level) _reload;
  final Future<void> Function(String id) _switchHome;
  final String fallbackHomeId;

  List<SshProfile> _lastProfiles;
  StreamSubscription<SshProfileState>? _profileSub;
  StreamSubscription<StoragePlaneChange>? _storageSub;

  /// The invalidation queued while a drain is in flight. Requests never
  /// downgrade: a pending `switchHome` outranks `full`, which outranks
  /// `indexOnly` — the drain coalesces a burst into the strongest request.
  _PendingInvalidation? _pending;
  var _draining = false;
  var _drainScheduled = false;

  /// Starts routing events. Must be called before app-data bootstrap runs so
  /// the baseline profile list is primed from [initialProfiles].
  void start() {
    _profileSub ??= _profileStates.listen(_onProfileState);
    _storageSub ??= _storageChanges.listen(_onStoragePlaneChange);
  }

  /// Unsubscribes from both streams. A drain already in flight still runs to
  /// completion (a pending invalidation is never dropped).
  void stop() {
    _profileSub?.cancel();
    _profileSub = null;
    _storageSub?.cancel();
    _storageSub = null;
  }

  void _onProfileState(SshProfileState state) {
    if (listEquals(_lastProfiles, state.profiles)) return; // re-emit, no diff
    final previous = _lastProfiles;
    _lastProfiles = List<SshProfile>.of(state.profiles);
    switch (resolveHomeSshProfileImpact(
      homeTargetId: _homeTargetId(),
      previous: previous,
      next: state.profiles,
    )) {
      case HomeSshProfileImpact.none:
        return;
      case HomeSshProfileImpact.homeConnectionChanged:
        _request(_PendingInvalidation.reloadFull);
      case HomeSshProfileImpact.homeProfileMissing:
        _request(_PendingInvalidation.switchHome);
    }
  }

  void _onStoragePlaneChange(StoragePlaneChange change) {
    // A no-op re-emit of the identical context carries no invalidation.
    if (identical(change.oldContext, change.newContext)) return;
    _request(_PendingInvalidation.reloadFull);
  }

  void _request(_PendingInvalidation request) {
    final pending = _pending;
    _pending = pending == null || request.rank >= pending.rank
        ? request
        : pending;
    if (_draining || _drainScheduled) return;
    // Defer the drain to the next event-loop turn so a burst of events (e.g.
    // two rapid profile diffs delivered in back-to-back microtasks) collapses
    // into one reload call.
    _drainScheduled = true;
    unawaited(
      Future<void>.delayed(Duration.zero).then((_) => _drain()),
    );
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    _draining = true;
    try {
      while (true) {
        final pending = _pending;
        if (pending == null) break;
        _pending = null;
        try {
          switch (pending) {
            case _PendingInvalidation.reloadIndexOnly:
              await _reload(ReloadLevel.indexOnly);
            case _PendingInvalidation.reloadFull:
              await _reload(ReloadLevel.full);
            case _PendingInvalidation.switchHome:
              await _switchHome(fallbackHomeId);
          }
        } on Object catch (error, stackTrace) {
          appLogger.e(
            '[storage] home invalidation reload failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      _draining = false;
      if (_pending != null && !_drainScheduled) {
        _drainScheduled = true;
        unawaited(
          Future<void>.delayed(Duration.zero).then((_) => _drain()),
        );
      }
    }
  }
}

enum _PendingInvalidation {
  reloadIndexOnly(1),
  reloadFull(2),
  switchHome(3);

  const _PendingInvalidation(this.rank);

  /// Precedence for coalescing — a stronger request replaces a weaker one.
  final int rank;
}
