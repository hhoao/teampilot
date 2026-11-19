import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
import '../repositories/plane_ssh_profile_repository.dart';
import '../repositories/connection_store.dart';
import '../repositories/catalog_store.dart';
import '../services/storage/home_storage.dart';
import '../utils/logging/logger.dart';
import 'ssh_profile_cubit.dart';

/// Global catalog of workload hosts stored on the home plane (B source).
///
/// Distinct from the device-local [SshProfileCubit] (A source, used only for
/// home binding / StartupGate / onboarding). Reads the plane's shared
/// `ssh_profiles/profiles.json` through [PlaneSshProfileRepository], so every
/// workload consumer (status bar, workspace MCP, remote sessions) sees the
/// plane's servers rather than this device's connection targets. Emits
/// [SshProfileState] so consumers reuse the shape exposed by the A-source
/// cubit.
///
/// A single long-lived instance is injected via `BlocProvider.value`, so a
/// home-plane swap must re-emit on the same instance rather than replace it:
/// the cubit owns the [HomeStorage.changes] subscription, whose events trigger
/// [load]. [close] cancels that subscription (shell teardown). A dropped plane
/// / failed read yields an empty catalog — it never throws and never falls back
/// to the A source.
class SshWorkloadProfileCubit extends Cubit<SshProfileState> {
  SshWorkloadProfileCubit({
    required HomeStorage storage,
    required ConnectionStore connections,
  }) : _storage = storage,
       _connections = connections,
       super(const SshProfileState()) {
    _changesSub = storage.changes.listen((_) => unawaited(load()));
  }

  final HomeStorage _storage;
  final ConnectionStore _connections;

  StreamSubscription<StoragePlaneChange>? _changesSub;

  /// The in-flight [load] chain, or null when idle.
  Future<void>? _loadFuture;

  /// A [load] that arrives while a read is in flight is not dropped: it flags
  /// exactly one re-read once the current read finishes. A swap published
  /// during a slow plane read is therefore observed instead of coalesced away
  /// (the in-flight read completes against the old transport).
  bool _pendingReload = false;

  Future<void> load() {
    final inFlight = _loadFuture;
    if (inFlight != null) {
      _pendingReload = true;
      return inFlight;
    }
    final chain = _runLoads();
    _loadFuture = chain;
    return chain;
  }

  Future<void> _runLoads() async {
    try {
      do {
        _pendingReload = false;
        await _doLoad();
      } while (_pendingReload && !isClosed);
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> _doLoad() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    // Fresh repository per read (B-source contract). Plane switches are picked
    // up by the changes subscription queuing a re-read, not by this rebuild:
    // the repositories resolve storage through lazy getters and
    // HomeStorage.swap mutates the same storage in place.
    final repository = PlaneSshProfileRepository(
      storage: _storage,
      connections: _connections,
      catalog: CatalogStore(storage: _storage),
    );
    List<SshProfile> profiles;
    try {
      profiles = await repository.loadAll();
    } on Object catch (error, stackTrace) {
      // The home plane is unreachable: the workload catalog is empty. Never
      // fall back to the device-local A source and never surface the error.
      AppLogger.instance.w(
        '[ssh-workload] home-plane catalog read failed; emitting empty',
        error: error,
        stackTrace: stackTrace,
      );
      profiles = const <SshProfile>[];
    }
    if (isClosed) return;
    emit(state.copyWith(profiles: profiles, isLoading: false));
  }

  @override
  Future<void> close() async {
    final sub = _changesSub;
    _changesSub = null;
    if (sub != null) await sub.cancel();
    await super.close();
  }
}
