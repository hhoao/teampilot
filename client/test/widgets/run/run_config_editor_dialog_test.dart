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
import 'package:teampilot/services/run/process_launch_schema.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';
import 'package:teampilot/widgets/run/run_config_editor_dialog.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _processConfig({
  String id = 'api',
  String name = 'API',
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

class _FakeProcessLauncher implements RunProcessLauncher {
  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
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

/// Store-backed platform so persist/delete round-trip through [LaunchConfigStore].
class _StoreBackedPlatform implements RunPlatformApi {
  _StoreBackedPlatform({LaunchConfigStore? store})
    : store = store ?? LaunchConfigStore(io: MemoryLaunchConfigIo()),
      sessionManager = RunSessionManager(
        executor: _FakeProcessLauncher(),
        adapters: _FakeAdapterLauncher(),
      );

  final LaunchConfigStore store;
  @override
  final RunSessionManager sessionManager;

  var persistCalls = 0;

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
  ) => const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) {
    if (owned.configuration.type == ProcessLaunchSchema.typeName) {
      return ProcessLaunchSchema.validate(owned.configuration);
    }
    return const [];
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

  @override
  Map<String, Object?>? configurationSchema(String type) {
    if (type == ProcessLaunchSchema.typeName) {
      return Map<String, Object?>.from(ProcessLaunchSchema.configurationSchema);
    }
    return null;
  }

  @override
  List<String> kindsFor(String type) => const ['run'];
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RunCubit cubit,
  OwnedLaunchConfiguration? initial,
  bool createNew = false,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<RunCubit>.value(
        value: cubit,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                key: const Key('open-editor'),
                onPressed: () {
                  showRunConfigEditorDialog(
                    context,
                    workspaceId: 'ws-1',
                    initial: initial,
                    createNew: createNew,
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-editor')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _waitUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('OK saves via cubit and closes', (tester) async {
    final platform = _StoreBackedPlatform();
    await platform.seed(_processConfig());
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await _pumpEditor(
      tester,
      cubit: cubit,
      initial: cubit.state.configurations.single,
    );

    expect(find.text('Edit configuration'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('launch-config-field-name')),
      'API Server',
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('run-config-editor-ok')));
    await tester.tap(find.byKey(const Key('run-config-editor-ok')));
    await _waitUntilGone(tester, find.text('Edit configuration'));

    expect(platform.persistCalls, 1);
    expect(find.text('Edit configuration'), findsNothing);
    expect(cubit.state.configurations.single.configuration.name, 'API Server');
    await cubit.close();
  });

  testWidgets('Cancel discards without save', (tester) async {
    final platform = _StoreBackedPlatform();
    await platform.seed(_processConfig());
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await _pumpEditor(
      tester,
      cubit: cubit,
      initial: cubit.state.configurations.single,
    );

    await tester.enterText(
      find.byKey(const Key('launch-config-field-name')),
      'Changed',
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(find.byKey(const Key('run-config-editor-cancel')));
    await _waitUntilFound(tester, find.text('Discard changes?'));

    await tester.tap(find.text('Discard'));
    await _waitUntilGone(tester, find.text('Edit configuration'));

    expect(find.text('Edit configuration'), findsNothing);
    expect(platform.persistCalls, 0);
    expect(cubit.state.configurations.single.configuration.name, 'API');
    await cubit.close();
  });

  testWidgets('create new opens add configuration title', (tester) async {
    final platform = _StoreBackedPlatform();
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    await cubit.load();

    await _pumpEditor(tester, cubit: cubit, createNew: true);

    expect(find.text('Add configuration'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('multi-folder create shows folder dropdown', (tester) async {
    const other = WorkspaceFolder(path: '/other');
    final platform = _StoreBackedPlatform();
    final cubit = RunCubit(
      platform: platform,
      folders: const [_folder, other],
    );
    await cubit.load();

    await _pumpEditor(tester, cubit: cubit, createNew: true);

    expect(find.text('Add configuration'), findsOneWidget);
    expect(find.byKey(const Key('run-config-folder-dropdown')), findsOneWidget);
    expect(find.text('Select folder'), findsOneWidget);
    await cubit.close();
  });
}
