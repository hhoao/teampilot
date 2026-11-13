import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
import '../repositories/plane_ssh_profile_repository.dart';
import '../repositories/remote_target_repository.dart';
import '../repositories/ssh_server_profile_repository.dart';
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
/// the cubit owns the [HomeStorage.changes] subscription and rebuilds its
/// repository on every [load]. [close] cancels that subscription (shell
/// teardown). A dropped plane / failed read yields an empty catalog — it never
/// throws and never falls back to the A source.
class SshWorkloadProfileCubit extends Cubit<SshProfileState> {
  SshWorkloadProfileCubit({
    required HomeStorage storage,
    RemoteTargetRepository? deviceTargets,
  }) : _storage = storage,
       _deviceTargets = deviceTargets,
       super(const SshProfileState()) {
    _changesSub = storage.changes.listen((_) => unawaited(load()));
  }

  final HomeStorage _storage;
  final RemoteTargetRepository? _deviceTargets;

  StreamSubscription<StoragePlaneChange>? _changesSub;

  /// Single-flight: boot, home-plane swaps, and manual refresh may overlap;
  /// coalescing collapses them into one plane read.
  Future<void>? _loadFuture;

  Future<void> load() => _loadFuture ??=
      _doLoad().whenComplete(() => _loadFuture = null);

  Future<void> _doLoad() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true));
    // Rebuild per load so a swap (which mutates [HomeStorage] in place) is
    // always read through a repository bound to the current plane.
    final repository = PlaneSshProfileRepository(
      storage: _storage,
      servers: SshServerProfileRepository(storage: _storage),
      deviceTargets: _deviceTargets,
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
