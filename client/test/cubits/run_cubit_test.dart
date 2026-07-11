import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';
import 'package:teampilot/services/run/process_run_executor.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _processConfig({
  String id = 'api',
  String command = 'true',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: id,
      type: 'process',
      command: command,
    ),
  );
}

OwnedLaunchConfiguration _flutterConfig({String id = 'app'}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: id,
      type: 'flutter',
      extras: const {'device': 'linux'},
    ),
  );
}

class _FakeProcessLauncher implements RunProcessLauncher {
  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    final exit = Completer<int>();
    return RunLaunchHandle(
      exitCode: exit.future,
      stop: () async {
        if (!exit.isCompleted) exit.complete(130);
      },
    );
  }
}

class FakeRunExecutor implements RunProcessLauncher {
  FakeRunExecutor({this.hangOnStart = false});

  final bool hangOnStart;
  final startedSessionIds = <String>[];
  var stopCount = 0;

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    startedSessionIds.add(sessionId);
    if (hangOnStart) {
      final exitCompleter = Completer<int>();
      return RunLaunchHandle(
        exitCode: exitCompleter.future,
        stop: () async {
          stopCount++;
          if (!exitCompleter.isCompleted) exitCompleter.complete(130);
        },
      );
    }
    return RunLaunchHandle(
      exitCode: Future.value(0),
      stop: () async {
        stopCount++;
      },
    );
  }
}

class _FakeAdapterLauncher implements RunAdapterLauncher {
  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    throw UnimplementedError();
  }
}

/// Minimal platform surface for cubit tests — real store/manager where useful.
class FakeRunPlatform implements RunPlatformApi {
  FakeRunPlatform({
    List<OwnedLaunchConfiguration>? configurations,
    List<OwnedLaunchCompound>? compounds,
    List<LaunchOption>? options,
    Stream<List<LaunchOption>>? optionsChanged,
    Stream<List<LaunchAdapterConfigurationEntry>>? configurationsChanged,
    RunSessionManager? sessionManager,
    List<String> Function(Object configuration)? validate,
  }) : configurations = configurations ?? [_processConfig()],
       compounds = compounds ?? const [],
       _options = options ?? const [],
       _optionsChanged = optionsChanged,
       _configurationsChanged = configurationsChanged,
       sessionManager =
           sessionManager ??
           RunSessionManager(
             executor: _FakeProcessLauncher(),
             adapters: _FakeAdapterLauncher(),
           ),
       _validate = validate ?? _defaultValidate;

  static List<String> _defaultValidate(Object configuration) => const [];

  List<OwnedLaunchConfiguration> configurations;
  List<OwnedLaunchCompound> compounds;
  final List<LaunchOption> _options;
  final Stream<List<LaunchOption>>? _optionsChanged;
  final Stream<List<LaunchAdapterConfigurationEntry>>? _configurationsChanged;
  @override
  final RunSessionManager sessionManager;
  final List<String> Function(Object configuration) _validate;

  final optionValuesWritten = <String, Object?>{};
  var provideOptionsCalls = 0;
  ConfigureActionResult? configureActionResult;
  String? lastOpenLaunchJsonPath;
  var persistConfigurationCalls = 0;
  LaunchConfiguration? lastPersistedConfiguration;

  @override
  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  ) async => configurations;

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) async => compounds;

  @override
  Stream<List<RunSession>> get sessionsStream => sessionManager.sessionsStream;

  @override
  List<RunSession> get sessions => sessionManager.sessions;

  @override
  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream =>
      _configurationsChanged ?? const Stream.empty();

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async {
    provideOptionsCalls++;
    return _options;
  }

  @override
  Stream<List<LaunchOption>> optionsChangedFor(OwnedLaunchConfiguration owned) {
    return _optionsChanged ?? const Stream.empty();
  }

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) {
    return _validate(owned.configuration);
  }

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) {
    return sessionManager.start(owned);
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
  }) async {
    return configureActionResult ??
        const ConfigureActionResult(cancelled: true);
  }

  @override
  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) async {
    persistConfigurationCalls++;
    lastPersistedConfiguration = configuration;
  }

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

void main() {
  test('run selected process config creates session', () async {
    final platform = FakeRunPlatform();
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    final key = platform.configurations.single.selectionKey;
    await cubit.select(key);
    await cubit.runSelected();
    expect(cubit.state.sessions, isNotEmpty);
    expect(cubit.state.sessions.single.status, RunSessionStatus.running);
    await cubit.close();
  });

  test('select loads options; setOption updates state', () async {
    final optionsController = StreamController<List<LaunchOption>>.broadcast();
    final platform = FakeRunPlatform(
      configurations: [_flutterConfig()],
      options: [
        const LaunchOption(
          id: 'device',
          label: 'Device',
          type: LaunchOptionType.choice,
          value: 'linux',
          choices: [
            LaunchOptionChoice(value: 'chrome', label: 'Chrome'),
            LaunchOptionChoice(value: 'linux', label: 'Linux'),
          ],
        ),
      ],
      optionsChanged: optionsController.stream,
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    expect(cubit.state.options, isNotEmpty);
    expect(platform.provideOptionsCalls, 1);
    cubit.setOption('device', 'chrome');
    expect(cubit.state.optionValues['device'], 'chrome');
    await cubit.close();
    await optionsController.close();
  });

  test('actions from configurationsChanged appear in state', () async {
    final actionsController =
        StreamController<List<LaunchAdapterConfigurationEntry>>.broadcast();
    final platform = FakeRunPlatform(
      configurationsChanged: actionsController.stream,
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    actionsController.add([
      const LaunchAdapterConfigurationEntry(
        id: 'select_entry',
        name: 'Select entry…',
        type: 'flutter',
        isAction: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.actions.any((a) => a.isAction), isTrue);
    await cubit.close();
    await actionsController.close();
  });

  test('runSelected sets errorMessage when schema invalid', () async {
    final platform = FakeRunPlatform(
      validate: (_) => const ['command is required'],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await cubit.runSelected();
    expect(cubit.state.errorMessage, contains('command'));
    expect(cubit.state.sessions, isEmpty);
    await cubit.close();
  });

  test('openLaunchJson returns selected config owning path', () async {
    final platform = FakeRunPlatform();
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    final path = await cubit.openLaunchJson();
    expect(path, '/proj/.teampilot/launch.json');
    await cubit.close();
  });

  test('stopSession stops running session and updates state', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final platform = FakeRunPlatform(
      sessionManager: RunSessionManager(
        executor: executor,
        adapters: _FakeAdapterLauncher(),
      ),
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await cubit.runSelected();
    final sessionId = cubit.state.sessions.single.id;
    expect(cubit.state.sessions.single.status, RunSessionStatus.running);

    await cubit.stopSession(sessionId);
    expect(cubit.state.sessions.single.status, RunSessionStatus.exited);
    expect(executor.stopCount, 1);
    await cubit.close();
    await platform.sessionManager.dispose();
  });

  test('restartSession replaces session with a new running one', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final platform = FakeRunPlatform(
      sessionManager: RunSessionManager(
        executor: executor,
        adapters: _FakeAdapterLauncher(),
      ),
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await cubit.runSelected();
    final originalId = cubit.state.sessions.single.id;

    await cubit.restartSession(originalId);
    final running = cubit.state.sessions
        .where((s) => s.status == RunSessionStatus.running)
        .toList();
    expect(running, hasLength(1));
    expect(running.single.id, isNot(originalId));
    expect(executor.startedSessionIds, hasLength(2));
    await cubit.close();
    await platform.sessionManager.dispose();
  });

  test('stopCompound stops all listed sessions', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final platform = FakeRunPlatform(
      configurations: [
        _processConfig(id: 'a'),
        _processConfig(id: 'b'),
      ],
      sessionManager: RunSessionManager(
        executor: executor,
        adapters: _FakeAdapterLauncher(),
      ),
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    await cubit.select(platform.configurations[0].selectionKey);
    await cubit.runSelected();
    await cubit.select(platform.configurations[1].selectionKey);
    await cubit.runSelected();
    final ids = cubit.state.sessions.map((s) => s.id).toList();
    expect(ids, hasLength(2));

    await cubit.stopCompound(ids);
    expect(
      cubit.state.sessions.every((s) => s.status == RunSessionStatus.exited),
      isTrue,
    );
    await cubit.close();
    await platform.sessionManager.dispose();
  });

  test('configureAction persists valid configuration and reloads', () async {
    final platform = FakeRunPlatform(
      validate: (config) {
        final launch = config as LaunchConfiguration;
        if (launch.type == 'flutter' && !launch.extras.containsKey('device')) {
          return const ['device is required'];
        }
        return const [];
      },
    )..configureActionResult = const ConfigureActionResult(
        persist: true,
        configuration: {
          'id': 'app',
          'name': 'app',
          'type': 'flutter',
          'device': 'linux',
        },
      );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await cubit.configureAction(
      actionId: 'pick_device',
      type: 'flutter',
      result: const {'device': 'linux'},
    );

    expect(platform.persistConfigurationCalls, 1);
    expect(platform.lastPersistedConfiguration?.id, 'app');
    expect(cubit.state.errorMessage, isNull);
    await cubit.close();
  });

  test('configureAction sets errorMessage when persisted config fails schema', () async {
    final platform = FakeRunPlatform(
      validate: (_) => const ['device is required'],
    )..configureActionResult = const ConfigureActionResult(
        persist: true,
        configuration: {
          'id': 'app',
          'name': 'app',
          'type': 'flutter',
        },
      );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await cubit.configureAction(
      actionId: 'pick_device',
      type: 'flutter',
      result: const {},
    );

    expect(platform.persistConfigurationCalls, 0);
    expect(cubit.state.errorMessage, contains('device'));
    await cubit.close();
  });
}
