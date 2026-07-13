import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_client.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/launch_type_registrar.dart';
import 'package:teampilot/services/run/launch_type_registry.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';

const _folder = WorkspaceFolder(path: '/proj');

LaunchTypeContribution _flutterContrib() {
  return LaunchTypeContribution(
    extensionId: 'ext.flutter',
    type: 'flutter',
    kinds: const ['run'],
    adapterCommand: r'${extensionPath}/bin/adapter',
    adapterRuntime: 'workspace',
    lifecycle: LaunchAdapterLifecycle.sticky,
    configurationSchema: const {
      'type': 'object',
      'required': ['device'],
      'properties': {
        'device': {'type': 'string'},
      },
    },
  );
}

class _FakeProcessLauncher implements RunProcessLauncher {
  var launchCount = 0;

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
    String? preferTerminalEntryId,
  }) async {
    launchCount++;
    return RunLaunchHandle(
      exitCode: Future.value(0),
      stop: () async {},
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

RunPlatform _platform({
  LaunchTypeRegistry? registry,
  RunSessionManager? sessionManager,
}) {
  final reg = registry ?? LaunchTypeRegistry.withBuiltIns();
  final launcher = _FakeProcessLauncher();
  final mgr =
      sessionManager ??
      RunSessionManager(
        executor: launcher,
        adapters: _FakeAdapterLauncher(),
      );
  return RunPlatform(
    store: LaunchConfigStore(io: MemoryLaunchConfigIo()),
    registry: reg,
    sessionManager: mgr,
    adapterClient: LaunchAdapterClient(
      extensionPathResolver: (_) => '/ext',
    ),
    registrar: LaunchTypeRegistrar(
      extensions: const [],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext',
    ),
  );
}

void main() {
  test('kindsFor and configurationSchema expose registry metadata', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(
      LaunchTypeContribution(
        extensionId: 'ext.debug',
        type: 'debuggable',
        kinds: const ['run', 'debug'],
        adapterCommand: r'${extensionPath}/bin/adapter',
        adapterRuntime: 'workspace',
        lifecycle: LaunchAdapterLifecycle.sticky,
        configurationSchema: const {
          'type': 'object',
          'required': ['target'],
          'properties': {
            'target': {'type': 'string'},
          },
        },
      ),
    );
    final platform = _platform(registry: reg);

    expect(platform.kindsFor('shellScript'), ['run']);
    expect(platform.kindsFor('process'), ['run']);
    expect(platform.kindsFor('debuggable'), ['run', 'debug']);
    expect(platform.kindsFor('unknown'), ['run']);

    final shellSchema = platform.configurationSchema('shellScript');
    expect(shellSchema, isNotNull);
    expect(shellSchema!['required'], contains('execute'));

    expect(platform.configurationSchema('process'), isNull);

    final debugSchema = platform.configurationSchema('debuggable');
    expect(debugSchema, isNotNull);
    expect(debugSchema!['required'], ['target']);
    expect(platform.configurationSchema('unknown'), isNull);
  });

  test('isTypeAvailable is always true for shellScript', () {
    final platform = _platform();
    expect(
      platform.isTypeAvailable('shellScript', targetId: 'local'),
      isTrue,
    );
    expect(
      platform.isTypeAvailable('process', targetId: 'ssh:box'),
      isFalse,
    );
  });

  test('validateConfiguration validates shellScript after variable expand', () {
    final platform = _platform();
    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'smoke',
        name: 'smoke',
        type: 'shellScript',
        extras: {
          'execute': 'scriptFile',
          'scriptPath': r'${workspaceFolder}/scripts/smoke.sh',
        },
      ),
    );

    expect(platform.validateConfiguration(owned), isEmpty);

    final missing = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'bad',
        name: 'bad',
        type: 'shellScript',
        extras: {'execute': 'scriptFile', 'scriptPath': ''},
      ),
    );
    expect(
      platform.validateConfiguration(missing),
      contains(contains('scriptPath')),
    );
  });

  test('validateConfiguration reports extension schema errors', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(_flutterContrib());
    reg.setAvailability(
      'flutter',
      targetId: WorkspaceFolder.localTargetId,
      available: true,
    );
    final platform = _platform(registry: reg);

    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'app',
        name: 'app',
        type: 'flutter',
      ),
    );

    final errors = platform.validateConfiguration(owned);
    expect(errors, isNotEmpty);
    expect(errors.single, contains('device'));
  });

  test('start rejects unavailable extension type on folder target', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(_flutterContrib());
    reg.setAvailability(
      'flutter',
      targetId: WorkspaceFolder.localTargetId,
      available: false,
    );
    final launcher = _FakeProcessLauncher();
    final platform = _platform(
      registry: reg,
      sessionManager: RunSessionManager(
        executor: launcher,
        adapters: _FakeAdapterLauncher(),
      ),
    );

    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'app',
        name: 'app',
        type: 'flutter',
        extras: const {'device': 'linux'},
      ),
    );

    expect(
      platform.validateConfiguration(owned),
      contains(contains('not available')),
    );
    await expectLater(
      platform.start(owned),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not available'),
        ),
      ),
    );
    expect(platform.sessions, isEmpty);
    expect(launcher.launchCount, 0);
    await platform.sessionManager.dispose();
  });

  test('start rejects unavailable type on remote folder target', () async {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(_flutterContrib());
    reg.setAvailability(
      'flutter',
      targetId: WorkspaceFolder.localTargetId,
      available: true,
    );
    final platform = _platform(registry: reg);

    final owned = OwnedLaunchConfiguration(
      owner: const WorkspaceFolder(path: '/proj', targetId: 'ssh:box'),
      configuration: const LaunchConfiguration(
        id: 'app',
        name: 'app',
        type: 'flutter',
        extras: const {'device': 'linux'},
      ),
    );

    expect(
      platform.validateConfiguration(owned),
      contains(contains('ssh:box')),
    );
    await expectLater(platform.start(owned), throwsA(isA<StateError>()));
    await platform.sessionManager.dispose();
  });
}
