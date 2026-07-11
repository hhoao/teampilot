import 'dart:async';

import '../../cubits/run_cubit.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/run/run_session.dart';
import '../../models/workspace_folder.dart';
import '../run/launch_adapter_protocol.dart';
import '../run/launch_config_store.dart';
import '../run/run_platform.dart';
import '../run/run_session_manager.dart';
import '../run/workspace_run_platform_factory.dart';

/// Retains per-tab [RunCubit]s so returning to a workspace tab keeps Run state.
///
/// Mirrors [WorkspaceToolsScopeRegistry]: create on first use, close on tab
/// close / app shutdown.
class WorkspaceRunRegistry {
  WorkspaceRunRegistry({
    required WorkspaceRunPlatformFactory platformFactory,
  }) : _platformFactory = platformFactory;

  final WorkspaceRunPlatformFactory _platformFactory;
  final Map<String, RunCubit> _cubits = <String, RunCubit>{};
  final Map<String, Future<void>> _loadFutures = <String, Future<void>>{};

  /// Returns the cubit for [tabScopeId], creating one when absent.
  ///
  /// [folders] are snapshotted at creation; callers that change folder topology
  /// should [removeScope] and recreate.
  RunCubit cubitFor({
    required String tabScopeId,
    required String workspaceId,
    required List<WorkspaceFolder> folders,
  }) {
    final key = tabScopeId.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(tabScopeId, 'tabScopeId', 'must not be empty');
    }
    final existing = _cubits[key];
    if (existing != null && !existing.isClosed) return existing;

    final proxy = _DeferredRunPlatform();
    final cubit = RunCubit(platform: proxy, folders: folders);
    _cubits[key] = cubit;

    _loadFutures[key] = () async {
      try {
        final platform = await _platformFactory.create(
          workspaceId: workspaceId,
        );
        proxy.bind(platform);
        if (!cubit.isClosed) await cubit.load();
      } catch (error) {
        proxy.fail(error);
        if (!cubit.isClosed) cubit.reportError(error.toString());
      }
    }();

    return cubit;
  }

  /// Completes when the cubit's platform has been built and [RunCubit.load]
  /// has finished (or failed).
  Future<void> ensureLoaded(String tabScopeId) {
    final key = tabScopeId.trim();
    return _loadFutures[key] ?? Future<void>.value();
  }

  void removeScope(String tabScopeId) {
    final key = tabScopeId.trim();
    if (key.isEmpty) return;
    _loadFutures.remove(key);
    _cubits.remove(key)?.close();
  }

  void dispose() {
    _loadFutures.clear();
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}

/// Forwards to a real [RunPlatformApi] once [bind] is called.
class _DeferredRunPlatform implements RunPlatformApi, RunPlatformDeferred {
  RunPlatformApi? _inner;
  Object? _error;
  final Completer<void> _ready = Completer<void>();

  @override
  Future<void> get whenReady => _ready.future;

  void bind(RunPlatformApi platform) {
    _inner = platform;
    if (!_ready.isCompleted) _ready.complete();
  }

  void fail(Object error) {
    _error = error;
    if (!_ready.isCompleted) _ready.completeError(error);
  }

  Future<RunPlatformApi> _awaitInner() async {
    await _ready.future;
    final inner = _inner;
    if (inner != null) return inner;
    throw _error ?? StateError('Run platform failed to initialize');
  }

  @override
  RunSessionManager get sessionManager {
    final inner = _inner;
    if (inner != null) return inner.sessionManager;
    throw StateError('Run platform is still initializing');
  }

  @override
  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  ) async => (await _awaitInner()).listConfigurations(folders);

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) async => (await _awaitInner()).listCompounds(folders);

  @override
  Stream<List<RunSession>> get sessionsStream =>
      _inner?.sessionsStream ?? const Stream.empty();

  @override
  List<RunSession> get sessions => _inner?.sessions ?? const [];

  @override
  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream =>
      _inner?.actionsStream ?? const Stream.empty();

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async => (await _awaitInner()).provideOptions(owned);

  @override
  Stream<List<LaunchOption>> optionsChangedFor(
    OwnedLaunchConfiguration owned,
  ) => _inner?.optionsChangedFor(owned) ?? const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) {
    final inner = _inner;
    if (inner == null) return const ['Run platform is still initializing'];
    return inner.validateConfiguration(owned);
  }

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) async =>
      (await _awaitInner()).start(owned);

  @override
  Future<void> stop(String sessionId) async =>
      (await _awaitInner()).stop(sessionId);

  @override
  Future<RunSession> restart(String sessionId) async =>
      (await _awaitInner()).restart(sessionId);

  @override
  Future<void> stopCompound(List<String> sessionIds) async =>
      (await _awaitInner()).stopCompound(sessionIds);

  @override
  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    required String type,
    String targetId = WorkspaceFolder.localTargetId,
  }) async => (await _awaitInner()).configureAction(
    actionId: actionId,
    workspaceFolder: workspaceFolder,
    result: result,
    type: type,
    targetId: targetId,
  );

  @override
  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) async => (await _awaitInner()).persistConfiguration(
    folder: folder,
    configuration: configuration,
  );

  @override
  String launchJsonPath(WorkspaceFolder folder) {
    final inner = _inner;
    if (inner != null) return inner.launchJsonPath(folder);
    return LaunchConfigStore.launchConfigPath(folder);
  }

  @override
  Future<void> rebuildLaunchTypes() async =>
      (await _awaitInner()).rebuildLaunchTypes();

  @override
  bool isTypeAvailable(String type, {required String targetId}) =>
      _inner?.isTypeAvailable(type, targetId: targetId) ?? true;

  @override
  String? unavailableReason(String type, {required String targetId}) =>
      _inner?.unavailableReason(type, targetId: targetId);
}
