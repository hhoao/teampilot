import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _processConfig({
  String id = 'api',
  String name = 'api',
  String command = 'true',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: name,
      type: 'process',
      command: command,
    ),
  );
}

OwnedLaunchConfiguration _flutterConfig({
  String id = 'app',
  String name = 'app',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: name,
      type: 'flutter',
      extras: const {'device': 'linux'},
    ),
  );
}

class _FakeProcessLauncher implements RunProcessLauncher {
  _FakeProcessLauncher({this.hangOnStart = false});

  final bool hangOnStart;
  var stopCount = 0;

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    if (hangOnStart) {
      final exit = Completer<int>();
      return RunLaunchHandle(
        exitCode: exit.future,
        stop: () async {
          stopCount++;
          if (!exit.isCompleted) exit.complete(130);
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

/// Store-backed platform so persist/delete round-trip through [LaunchConfigStore].
class _StoreBackedPlatform implements RunPlatformApi {
  _StoreBackedPlatform({
    LaunchConfigStore? store,
    RunSessionManager? sessionManager,
    List<String> Function(OwnedLaunchConfiguration owned)? validate,
    Stream<List<LaunchOption>>? optionsChanged,
  }) : store = store ?? LaunchConfigStore(io: MemoryLaunchConfigIo()),
       sessionManager =
           sessionManager ??
           RunSessionManager(
             executor: _FakeProcessLauncher(),
             adapters: _FakeAdapterLauncher(),
           ),
       _validate = validate,
       _optionsChanged = optionsChanged;

  final LaunchConfigStore store;
  @override
  final RunSessionManager sessionManager;
  final List<String> Function(OwnedLaunchConfiguration owned)? _validate;
  final Stream<List<LaunchOption>>? _optionsChanged;

  var persistCalls = 0;
  var deleteCalls = 0;
  String? lastDeletedId;

  Future<void> seed(OwnedLaunchConfiguration owned) {
    return store.upsertConfiguration(
      folder: owned.owner,
      configuration: owned.configuration,
    );
  }

  @override
  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  ) => store.listConfigurations(folders: folders);

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) => store.listCompounds(folders: folders);

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
  ) => _optionsChanged ?? const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) {
    return _validate?.call(owned) ?? const [];
  }

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) {
    return sessionManager.start(owned);
  }

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
  }) async {
    final errors = validateConfiguration(
      OwnedLaunchConfiguration(owner: folder, configuration: configuration),
    );
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    persistCalls++;
    await store.upsertConfiguration(
      folder: folder,
      configuration: configuration,
    );
  }

  @override
  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  }) async {
    deleteCalls++;
    lastDeletedId = id;
    await store.deleteConfiguration(folder: folder, id: id);
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
  test('saveConfiguration persists and selects', () async {
    final platform = _StoreBackedPlatform();
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    final owned = _processConfig(id: 'web', name: 'web', command: 'npm start');
    await cubit.saveConfiguration(owned);

    expect(platform.persistCalls, 1);
    expect(cubit.state.configurations, hasLength(1));
    expect(cubit.state.configurations.single.configId, 'web');
    expect(cubit.state.selectedKey, owned.selectionKey);
    expect(cubit.state.errorMessage, isNull);
    await cubit.close();
  });

  test('saveConfiguration assigns id via normalized for empty draft', () async {
    final platform = _StoreBackedPlatform();
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    final draft = cubit.createConfiguration(folder: _folder, type: 'process');
    expect(draft.configuration.id, isEmpty);
    expect(draft.configuration.name, isEmpty);
    expect(draft.configuration.type, 'process');

    final named = OwnedLaunchConfiguration(
      owner: draft.owner,
      configuration: draft.configuration.copyWith(
        name: 'API Server',
        command: 'true',
      ),
    );
    await cubit.saveConfiguration(named);

    expect(cubit.state.configurations, hasLength(1));
    expect(cubit.state.configurations.single.configId, 'api-server');
    expect(
      cubit.state.selectedKey,
      cubit.state.configurations.single.selectionKey,
    );
    await cubit.close();
  });

  test('saveConfiguration validates via platform', () async {
    final platform = _StoreBackedPlatform(
      validate: (_) => const ['command is required'],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await cubit.saveConfiguration(_processConfig(command: ''));

    expect(platform.persistCalls, 0);
    expect(cubit.state.configurations, isEmpty);
    expect(cubit.state.errorMessage, contains('command'));
    await cubit.close();
  });

  test('deleteConfiguration removes and clears selection', () async {
    final platform = _StoreBackedPlatform();
    await platform.seed(_processConfig());
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    final key = cubit.state.configurations.single.selectionKey;
    await cubit.select(key);
    expect(cubit.state.selectedKey, key);

    await cubit.deleteConfiguration(cubit.state.configurations.single);

    expect(platform.deleteCalls, 1);
    expect(platform.lastDeletedId, 'api');
    expect(cubit.state.configurations, isEmpty);
    expect(cubit.state.selectedKey, isNull);
    await cubit.close();
  });

  test(
    'deleteConfiguration cancels options sub for selected config',
    () async {
      final optionsController = StreamController<List<LaunchOption>>.broadcast();
      final platform = _StoreBackedPlatform(
        optionsChanged: optionsController.stream,
      );
      await platform.seed(_flutterConfig());
      final cubit = RunCubit(platform: platform, folders: const [_folder]);
      await cubit.load();
      final owned = cubit.state.configurations.single;
      await cubit.select(owned.selectionKey);

      await cubit.deleteConfiguration(owned);

      expect(cubit.state.selectedKey, isNull);
      expect(cubit.state.options, isEmpty);
      optionsController.add([
        const LaunchOption(
          id: 'device',
          label: 'Device',
          type: LaunchOptionType.choice,
          value: 'chrome',
          choices: [
            LaunchOptionChoice(value: 'chrome', label: 'Chrome'),
            LaunchOptionChoice(value: 'linux', label: 'Linux'),
          ],
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.options, isEmpty);
      await cubit.close();
      await optionsController.close();
    },
  );

  test('deleteConfiguration when not running leaves sessions untouched', () async {
    final platform = _StoreBackedPlatform();
    await platform.seed(_processConfig(id: 'a'));
    await platform.seed(_processConfig(id: 'b'));
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    final first = cubit.state.configurations.firstWhere((c) => c.configId == 'a');
    final second = cubit.state.configurations.firstWhere((c) => c.configId == 'b');
    await cubit.select(second.selectionKey);

    await cubit.deleteConfiguration(first);

    expect(platform.deleteCalls, 1);
    expect(cubit.state.configurations.map((c) => c.configId), ['b']);
    expect(cubit.state.selectedKey, second.selectionKey);
    expect(cubit.state.sessions, isEmpty);
    await cubit.close();
  });

  test('deleteConfiguration stops running session first', () async {
    final launcher = _FakeProcessLauncher(hangOnStart: true);
    final platform = _StoreBackedPlatform(
      sessionManager: RunSessionManager(
        executor: launcher,
        adapters: _FakeAdapterLauncher(),
      ),
    );
    await platform.seed(_processConfig());
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();
    final owned = cubit.state.configurations.single;
    await cubit.select(owned.selectionKey);
    await cubit.runSelected();
    expect(cubit.state.sessions.single.status, RunSessionStatus.running);

    await cubit.deleteConfiguration(owned);

    expect(launcher.stopCount, 1);
    expect(platform.deleteCalls, 1);
    expect(cubit.state.configurations, isEmpty);
    expect(cubit.state.selectedKey, isNull);
    await cubit.close();
    await platform.sessionManager.dispose();
  });
}
