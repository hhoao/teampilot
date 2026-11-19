import 'dart:async';

import '../../cubits/home_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../services/ssh/ssh_connection_failure.dart';
import '../../services/ssh/ssh_home_connectivity_supervisor.dart';
import '../../services/storage/home_connect_attempt.dart';
import '../../services/storage/home_invalidation_service.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/home_target_store.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/storage/runtime_context_registry.dart';
import '../../utils/logging/logger.dart';
import 'managed_provider_control_plane.dart';

/// Owns the home-plane switch: persist the chosen home id, rebind the runtime
/// context registry, republish the plane through [storage], and reseed the
/// connection cubit onto the replacement target.
///
/// The controller owns no mutable state. The live home target, the published
/// active profile id, and the connectivity-watch baseline all stay shell-owned
/// and arrive as accessors ([readHomeTarget]/[writeHomeTarget],
/// [readActiveHomeProfileId]/[writeActiveHomeProfileId], and the
/// write-only [writeWatchedConnectivityKey]), so every write lands in the
/// shell's own variable.
///
/// The rest of the shell's seams arrive as accessors too:
/// [reinstallStorageContext] is assigned by the shell before this controller
/// is constructed, and [homeInvalidationService] is a shell `late final`
/// assigned once the graph is wired — only [rebindHomeStoragePlane] reads it,
/// and only at call time. No accessor points back at one of this controller's
/// own methods.
class HomePlaneSwitchController {
  HomePlaneSwitchController({
    required this.runtimeContexts,
    required this.sshProfiles,
    required this.storage,
    required this.managedProviders,
    required this.homeTargetStore,
    required this.homeTargetFromId,
    required this.sshProfileById,
    required this.sshProfileConnectivityKey,
    required this.sshHomeConnectivity,
    required this.homeConnectionCubit,
    required this.applyHomeEventTransport,
    required this.reinstallStorageContext,
    required this.readHomeTarget,
    required this.writeHomeTarget,
    required this.readActiveHomeProfileId,
    required this.writeActiveHomeProfileId,
    required this.writeWatchedConnectivityKey,
    required this.resetNavigation,
    required this.homeInvalidationService,
  });

  final RuntimeContextRegistry runtimeContexts;
  final SshProfileCubit sshProfiles;
  final HomeStorage storage;
  final ManagedProviderControlPlane managedProviders;
  final HomeTargetStore homeTargetStore;
  final RuntimeTarget Function(String id) homeTargetFromId;
  final SshProfile? Function(String id) sshProfileById;
  final String Function(SshProfile profile) sshProfileConnectivityKey;
  final SshHomeConnectivitySupervisor sshHomeConnectivity;
  final HomeConnectionCubit? homeConnectionCubit;
  final Future<void> Function({bool restart}) applyHomeEventTransport;
  final Future<void> Function() reinstallStorageContext;
  final RuntimeTarget Function() readHomeTarget;
  final void Function(RuntimeTarget target) writeHomeTarget;
  final String? Function() readActiveHomeProfileId;
  final void Function(String? profileId) writeActiveHomeProfileId;
  final void Function(String? key) writeWatchedConnectivityKey;

  /// Resets the navigator to the home route. Workspace routes (and the tabs
  /// they render) are scoped to the home plane: after a switch they reference
  /// the outgoing plane's workspace ids, which the shell cannot resolve on the
  /// replacement and renders as an empty body.
  final void Function() resetNavigation;
  final HomeInvalidationService Function() homeInvalidationService;

  Future<void> persistSshHomePathCacheIfLive() async {
    final home = readHomeTarget();
    if (home.kind != RuntimeKind.ssh) return;
    final pid = home.sshProfileId;
    if (pid == null || pid.isEmpty) return;
    final ctx = runtimeContexts.home();
    if (ctx.pathsFromCache) return;
    if (!sshProfiles.state.profiles.any((p) => p.id == pid)) {
      await sshProfiles.load();
    }
    await sshProfiles.updatePathCache(
      pid,
      home: ctx.home,
      appDataRoot: ctx.appDataRoot,
    );
  }

  /// Persists the chosen home id, rebinds the registry home, and republishes it
  /// through [storage].
  Future<void> setHomeTarget(String id) async {
    await managedProviders.invalidateForStorageContextChange();
    await homeTargetStore.save(id);
    final previousHomeId = readHomeTarget().id;
    final nextHomeTarget = homeTargetFromId(id);
    // Drop any cached wrapper for the destination target so rebindHome
    // materializes a fresh context (unchanged from the pre-swap sequence).
    if (id != previousHomeId) await runtimeContexts.dispose(id);
    await runtimeContexts.rebindHome(nextHomeTarget);
    writeHomeTarget(nextHomeTarget);
    final nextProfileId = nextHomeTarget.sshProfileId;
    writeActiveHomeProfileId(
      nextHomeTarget.kind == RuntimeKind.ssh &&
              nextProfileId != null &&
              nextProfileId.isNotEmpty
          ? nextProfileId
          : null,
    );
    // Publish the new home plane synchronously, then retire the outgoing
    // context — its registry entry is evicted and the SSH transport closed
    // only after in-flight ops drain (Task 5 deferred close).
    await storage.swap(runtimeContexts.home());
    await persistSshHomePathCacheIfLive();
  }

  /// Publishes the live SSH home plane after recovery. The shell's
  /// `reinstallStorageContext` re-resolves the target with the transport now
  /// live, so a successful swap means the whole app object graph can keep
  /// running on the SSH plane — no restart needed. Returns null on success, or
  /// the error kind to surface on the connection page when the swap failed (or
  /// still left a native plane).
  Future<HomeErrorKind?> rebindHomeStoragePlane() async {
    try {
      await homeInvalidationService().runSelfInitiatedSwap(
        reinstallStorageContext,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[boot] home storage plane rebind failed',
        error: error,
        stackTrace: stackTrace,
      );
      return isSshHostKeyFailure(error)
          ? HomeErrorKind.hostIdentityChanged
          : isSshAuthFailure(error)
          ? HomeErrorKind.authFailed
          : HomeErrorKind.transportError;
    }
    return storage.context.mode == StorageBackendMode.ssh
        ? null
        : HomeErrorKind.transportError;
  }

  Future<void> switchHomeTarget(String id) async {
    final previousSshProfileId = readActiveHomeProfileId();
    // Prime the edit-watch baseline before the switch publishes anything, so
    // the path-cache write inside setHomeTarget is not mistaken for a user
    // edit of the new target.
    final pendingTarget = homeTargetFromId(id);
    final pendingProfileId =
        pendingTarget.kind == RuntimeKind.ssh &&
            (pendingTarget.sshProfileId ?? '').isNotEmpty
        ? pendingTarget.sshProfileId
        : null;
    final pendingProfile = pendingProfileId == null
        ? null
        : sshProfileById(pendingProfileId);
    writeWatchedConnectivityKey(
      pendingProfile == null ? null : sshProfileConnectivityKey(pendingProfile),
    );
    final previousContext = storage.context;
    await setHomeTarget(
      id,
    ); // persists + rebinds home + republishes HomeStorage
    final nextContext = storage.context;
    if (previousContext.target.id != nextContext.target.id ||
        previousContext.appDataRoot != nextContext.appDataRoot) {
      // The plane identity changed: any workspace route/tab still pointing at
      // one of the outgoing plane's ids can no longer render (the shell has no
      // matching workspace and paints an empty body). Reset navigation as soon
      // as the replacement is published; the cubit/transport rebind below does
      // not depend on the route. A same-identity reinstall (reconnect) keeps
      // the current route.
      resetNavigation();
    }
    final nextSshProfileId = readActiveHomeProfileId();
    if (previousSshProfileId != nextSshProfileId) {
      // Latch the abandoned profile (in-flight attempts back out, timer is
      // dropped) and move the persistent retry loop to the new home — in one
      // supervisor command instead of two independent coordinator calls.
      sshHomeConnectivity.activateHome(nextSshProfileId);
    }
    // Reseed the connection cubit onto the new target. Its callbacks read
    // `activeHomeProfileId`, so without this the gate would keep showing the
    // connection page and 「继续重试」 would retry the abandoned home.
    final nextProfile = nextSshProfileId == null
        ? null
        : sshProfileById(nextSshProfileId);
    writeWatchedConnectivityKey(
      nextProfile == null ? null : sshProfileConnectivityKey(nextProfile),
    );
    final cubit = homeConnectionCubit;
    if (cubit != null && !cubit.isClosed) {
      cubit.rebind(
        profileId: nextSshProfileId,
        host: nextProfile?.host,
        port: nextProfile?.port,
      );
      if (nextSshProfileId == null) {
        // setHomeTarget already resolved and published the new non-SSH plane;
        // seed connected without replaying hot recovery.
        cubit.markInitial(HomeConnectResult.connected(runtimeContexts.home()));
      } else {
        // One bounded attempt against the replacement target: this is what
        // lets the gate leave the connection page once the new home connects.
        unawaited(cubit.retryNow());
      }
    }
    await applyHomeEventTransport(restart: true);
  }
}
