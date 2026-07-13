import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_client.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/launch_discover.dart';
import 'package:teampilot/services/run/launch_type_registrar.dart';
import 'package:teampilot/services/run/launch_type_registry.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';

const _folder = WorkspaceFolder(path: '/proj');

LaunchTypeContribution _flutterDiscoverContrib({
  Map<String, Object?> discoverConfiguration = const {
    'id': 'flutter',
    'name': 'Flutter',
    'device': 'linux',
  },
}) {
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
    discover: {
      'enabled': true,
      'globs': ['pubspec.yaml'],
      'configuration': discoverConfiguration,
    },
  );
}

class _FakeProcessLauncher implements RunProcessLauncher {
  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
    String? preferTerminalEntryId,
  }) async {
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
  required LaunchConfigStore store,
  required LaunchTypeRegistry registry,
}) {
  return RunPlatform(
    store: store,
    registry: registry,
    sessionManager: RunSessionManager(
      executor: _FakeProcessLauncher(),
      adapters: _FakeAdapterLauncher(),
    ),
    adapterClient: LaunchAdapterClient(extensionPathResolver: (_) => '/ext'),
    registrar: LaunchTypeRegistrar(
      extensions: const [],
      detector: (_) async => true,
      extensionPathFor: (_) => '/ext',
    ),
  );
}

void main() {
  late MemoryLaunchConfigIo memoryIo;
  late LaunchConfigStore store;
  late LaunchTypeRegistry registry;

  setUp(() {
    memoryIo = MemoryLaunchConfigIo();
    store = LaunchConfigStore(io: memoryIo);
    registry = LaunchTypeRegistry.withBuiltIns();
    registry.registerExtension(_flutterDiscoverContrib());
    registry.setAvailability(
      'flutter',
      targetId: WorkspaceFolder.localTargetId,
      available: true,
    );
  });

  Future<void> writeMarker(String relativePath) {
    return memoryIo.writeString(
      '${_folder.path}/$relativePath',
      'marker',
      targetId: _folder.targetId,
    );
  }

  test('glob discover returns recommendation when marker file exists', () async {
    await writeMarker('pubspec.yaml');

    final recommendations = await LaunchDiscover(io: memoryIo).discover(
      folders: const [_folder],
      registry: registry,
    );

    expect(recommendations, hasLength(1));
    expect(recommendations.single.owner, _folder);
    expect(recommendations.single.configuration.type, 'flutter');
    expect(recommendations.single.configuration.id, 'flutter');
    expect(recommendations.single.configuration.extras['device'], 'linux');
  });

  test('discover skips folders without matching globs', () async {
    final recommendations = await LaunchDiscover(io: memoryIo).discover(
      folders: const [_folder],
      registry: registry,
    );
    expect(recommendations, isEmpty);
  });

  test('discover skips configs already present in launch.json', () async {
    await writeMarker('pubspec.yaml');
    await store.upsertConfiguration(
      folder: _folder,
      configuration: const LaunchConfiguration(
        id: 'flutter',
        name: 'Flutter',
        type: 'flutter',
        extras: {'device': 'linux'},
      ),
    );
    final existing = await store.listConfigurations(folders: const [_folder]);

    final recommendations = await LaunchDiscover(io: memoryIo).discover(
      folders: const [_folder],
      registry: registry,
      existing: existing,
    );

    expect(recommendations, isEmpty);
  });

  test('RunPlatform discoverRecommendations delegates to LaunchDiscover', () async {
    await writeMarker('pubspec.yaml');
    final platform = _platform(store: store, registry: registry);

    expect(
      await platform.discoverRecommendations(const [_folder]),
      hasLength(1),
    );
    await platform.sessionManager.dispose();
  });

  test('refreshDiscover populates cubit recommendations', () async {
    await writeMarker('pubspec.yaml');
    final platform = _platform(store: store, registry: registry);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.recommendations, hasLength(1));
    expect(cubit.state.recommendations.single.configuration.type, 'flutter');
    await platform.sessionManager.dispose();
  });

  test('acceptRecommendation writes validated config into launch.json', () async {
    await writeMarker('pubspec.yaml');
    final platform = _platform(store: store, registry: registry);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);

    await cubit.load();
    final recommendation = cubit.state.recommendations.single;

    await cubit.acceptRecommendation(recommendation);

    final path = LaunchConfigStore.launchConfigPath(_folder);
    final raw = await memoryIo.readString(path, targetId: _folder.targetId);
    expect(raw, isNotNull);
    expect(raw, contains('"type": "flutter"'));
    expect(cubit.state.configurations, hasLength(1));
    expect(cubit.state.recommendations, isEmpty);
    expect(cubit.state.errorMessage, isNull);
    await platform.sessionManager.dispose();
  });

  test('acceptRecommendation reports schema validation errors', () async {
    await writeMarker('pubspec.yaml');
    final badRegistry = LaunchTypeRegistry.withBuiltIns();
    badRegistry.registerExtension(
      _flutterDiscoverContrib(
        discoverConfiguration: const {
          'id': 'flutter',
          'name': 'Flutter',
        },
      ),
    );
    badRegistry.setAvailability(
      'flutter',
      targetId: WorkspaceFolder.localTargetId,
      available: true,
    );

    final platform = _platform(store: store, registry: badRegistry);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);

    await cubit.load();
    final recommendation = cubit.state.recommendations.single;

    await cubit.acceptRecommendation(recommendation);

    expect(cubit.state.configurations, isEmpty);
    expect(cubit.state.errorMessage, contains('device'));
    await platform.sessionManager.dispose();
  });
}
