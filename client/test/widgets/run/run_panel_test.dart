import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';

import 'package:teampilot/widgets/run/run_panel.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _processConfig({
  String id = 'api',
  String name = 'API',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: name,
      type: 'process',
      command: 'echo',
    ),
  );
}

class _OutputLauncher implements RunProcessLauncher {
  final _outputBySession = <String, void Function(ProcessRunOutput)>{};
  final _exit = <String, Completer<int>>{};

  void emit(String sessionId, String data, {String category = 'stdout'}) {
    final onOutput = _outputBySession[sessionId];
    if (onOutput == null) {
      fail('no launcher callback for $sessionId');
    }
    onOutput(
      ProcessRunOutput(sessionId: sessionId, category: category, data: data),
    );
  }

  void complete(String sessionId, [int code = 0]) {
    final completer = _exit[sessionId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(code);
    }
  }

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    _outputBySession[sessionId] = onOutput;
    final exit = Completer<int>();
    _exit[sessionId] = exit;
    return RunLaunchHandle(
      exitCode: exit.future,
      stop: () async {
        if (!exit.isCompleted) exit.complete(130);
      },
    );
  }
}

class _NoopAdapter implements RunAdapterLauncher {
  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    throw UnimplementedError();
  }
}

class _FakePlatform implements RunPlatformApi {
  _FakePlatform({required this.configurations})
    : launcher = _OutputLauncher() {
    sessionManager = RunSessionManager(
      executor: launcher,
      adapters: _NoopAdapter(),
    );
  }

  final List<OwnedLaunchConfiguration> configurations;
  final _OutputLauncher launcher;
  @override
  late final RunSessionManager sessionManager;

  @override
  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  ) async => configurations;

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) async => const [];

  @override
  Stream<List<RunSession>> get sessionsStream => sessionManager.sessionsStream;

  @override
  List<RunSession> get sessions => sessionManager.sessions;

  @override
  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream =>
      const Stream.empty();

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async => const [];

  @override
  Stream<List<LaunchOption>> optionsChangedFor(
    OwnedLaunchConfiguration owned,
  ) => const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) =>
      const [];

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) =>
      sessionManager.start(owned);

  @override
  Future<List<String>> startCompound({
    required OwnedLaunchCompound owned,
    required List<OwnedLaunchConfiguration> documentConfigs,
  }) {
    return sessionManager.startCompound(
      compound: owned.compound,
      documentConfigs: documentConfigs,
    );
  }

  @override
  Future<void> stop(String sessionId) => sessionManager.stop(sessionId);

  @override
  Future<RunSession> restart(String sessionId) =>
      sessionManager.restart(sessionId);

  @override
  Future<void> stopCompound(List<String> sessionIds) =>
      sessionManager.stopCompound(sessionIds);

  @override
  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    required String type,
    String targetId = WorkspaceFolder.localTargetId,
  }) async => const ConfigureActionResult(cancelled: true);

  @override
  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) async {}

  @override
  String launchJsonPath(WorkspaceFolder folder) =>
      LaunchConfigStore.launchConfigPath(folder);

  @override
  Future<void> rebuildLaunchTypes() async {}

  @override
  Future<List<OwnedLaunchConfiguration>> discoverRecommendations(
    List<WorkspaceFolder> folders, {
    List<OwnedLaunchConfiguration> existing = const [],
  }) async => const [];

  @override
  bool isTypeAvailable(String type, {required String targetId}) => true;

  @override
  String? unavailableReason(String type, {required String targetId}) => null;
}

/// Mirrors [_DeferredRunPlatform]: sessionManager throws until [bind].
class _DeferredFakePlatform implements RunPlatformApi, RunPlatformDeferred {
  _DeferredFakePlatform() : _ready = Completer<void>();

  final Completer<void> _ready;
  RunPlatformApi? _inner;

  @override
  Future<void> get whenReady => _ready.future;

  void bind(RunPlatformApi platform) {
    _inner = platform;
    if (!_ready.isCompleted) _ready.complete();
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
  ) async => (await whenReady.then((_) => _inner!)).listConfigurations(folders);

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) async => (await whenReady.then((_) => _inner!)).listCompounds(folders);

  @override
  Stream<List<RunSession>> get sessionsStream =>
      _inner?.sessionsStream ?? const Stream.empty();

  @override
  List<RunSession> get sessions => _inner?.sessions ?? const [];

  @override
  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream =>
      const Stream.empty();

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async => const [];

  @override
  Stream<List<LaunchOption>> optionsChangedFor(
    OwnedLaunchConfiguration owned,
  ) => const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) =>
      const ['Run platform is still initializing'];

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) =>
      throw StateError('not ready');

  @override
  Future<List<String>> startCompound({
    required OwnedLaunchCompound owned,
    required List<OwnedLaunchConfiguration> documentConfigs,
  }) => throw StateError('not ready');

  @override
  Future<void> stop(String sessionId) => throw StateError('not ready');

  @override
  Future<RunSession> restart(String sessionId) =>
      throw StateError('not ready');

  @override
  Future<void> stopCompound(List<String> sessionIds) =>
      throw StateError('not ready');

  @override
  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    required String type,
    String targetId = WorkspaceFolder.localTargetId,
  }) async => const ConfigureActionResult(cancelled: true);

  @override
  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) async {}

  @override
  String launchJsonPath(WorkspaceFolder folder) =>
      LaunchConfigStore.launchConfigPath(folder);

  @override
  Future<void> rebuildLaunchTypes() async {}

  @override
  Future<List<OwnedLaunchConfiguration>> discoverRecommendations(
    List<WorkspaceFolder> folders, {
    List<OwnedLaunchConfiguration> existing = const [],
  }) async => const [];

  @override
  bool isTypeAvailable(String type, {required String targetId}) => true;

  @override
  String? unavailableReason(String type, {required String targetId}) => null;
}

Widget _host({required RunCubit cubit}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: BlocProvider<RunCubit>.value(
        value: cubit,
        child: const RunPanel(),
      ),
    ),
  );
}

void main() {
  testWidgets('mounts without error while platform is still initializing', (
    tester,
  ) async {
    final deferred = _DeferredFakePlatform();
    final cubit = RunCubit(platform: deferred, folders: const [_folder]);
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    expect(find.byKey(const Key('run-panel')), findsOneWidget);
    expect(find.text('Loading run output…'), findsOneWidget);

    final platform = _FakePlatform(configurations: const []);
    addTearDown(platform.sessionManager.dispose);
    deferred.bind(platform);
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading run output…'), findsNothing);
    expect(
      find.text('Run a configuration to see output here'),
      findsOneWidget,
    );
  });

  testWidgets('new session focuses a Run page', (tester) async {
    final platform = _FakePlatform(configurations: [_processConfig()]);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform.sessionManager.dispose);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    expect(find.byKey(const Key('run-panel')), findsOneWidget);
    expect(find.text('API'), findsNothing);

    await cubit.select('local|/proj|api');
    await cubit.runSelected();
    await tester.pump();
    await tester.pump();

    expect(cubit.state.sessions, hasLength(1));
    final sessionId = cubit.state.sessions.single.id;
    expect(find.text('API'), findsWidgets);
    expect(
      find.byKey(Key('run-session-page-$sessionId')),
      findsOneWidget,
    );
  });

  testWidgets('output appends to the focused session log', (tester) async {
    final platform = _FakePlatform(configurations: [_processConfig()]);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform.sessionManager.dispose);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));

    await cubit.select('local|/proj|api');
    await cubit.runSelected();
    await tester.pump();

    final sessionId = cubit.state.sessions.single.id;
    platform.launcher.emit(sessionId, 'hello from run\n');
    await tester.pump();

    expect(find.textContaining('hello from run'), findsOneWidget);

    platform.launcher.emit(sessionId, 'second line\n');
    await tester.pump();

    expect(find.textContaining('hello from run'), findsOneWidget);
    expect(find.textContaining('second line'), findsOneWidget);
  });
}
