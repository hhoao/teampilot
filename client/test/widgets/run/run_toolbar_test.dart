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
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/run/run_toolbar.dart';

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
      command: 'true',
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
      exitCode: Future<int>.value(0),
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

class _RecordingPlatform implements RunPlatformApi {
  _RecordingPlatform({
    required this.configurations,
    this.actions = const [],
    this.options = const [],
    this.recommendations = const [],
  }) : sessionManager = RunSessionManager(
         executor: _FakeProcessLauncher(),
         adapters: _FakeAdapterLauncher(),
       );

  final List<OwnedLaunchConfiguration> configurations;
  final List<LaunchAdapterConfigurationEntry> actions;
  final List<LaunchOption> options;
  final List<OwnedLaunchConfiguration> recommendations;

  @override
  final RunSessionManager sessionManager;

  var runSelectedCalls = 0;
  var configureActionCalls = 0;
  String? lastConfigureActionId;

  final _actionsController =
      StreamController<List<LaunchAdapterConfigurationEntry>>.broadcast();

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
      _actionsController.stream;

  void emitActions(List<LaunchAdapterConfigurationEntry> next) {
    _actionsController.add(next);
  }

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async => options;

  @override
  Stream<List<LaunchOption>> optionsChangedFor(
    OwnedLaunchConfiguration owned,
  ) => const Stream.empty();

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) =>
      const [];

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) async {
    runSelectedCalls++;
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
    configureActionCalls++;
    lastConfigureActionId = actionId;
    return const ConfigureActionResult(cancelled: true);
  }

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
  }) async => recommendations;

  @override
  bool isTypeAvailable(String type, {required String targetId}) => true;

  @override
  String? unavailableReason(String type, {required String targetId}) => null;
}

class _RecordingCubit extends RunCubit {
  _RecordingCubit({required super.platform, required super.folders});

  final setOptionCalls = <MapEntry<String, Object?>>[];

  @override
  void setOption(String id, Object? value) {
    setOptionCalls.add(MapEntry(id, value));
    super.setOption(id, value);
  }
}

Widget _host({required RunCubit cubit, RunActionPicker? pickActionResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(
      useMaterial3: true,
      extensions: [AppControlTheme.fromScale(AppTypographyScale.standard)],
    ),
    home: Scaffold(
      body: BlocProvider<RunCubit>.value(
        value: cubit,
        child: RunToolbar(
          workspaceId: 'ws-1',
          pickActionResult: pickActionResult,
          openLaunchJson: (_) async {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('dropdown lists configs and isAction items', (tester) async {
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
      actions: const [
        LaunchAdapterConfigurationEntry(
          id: 'pick-entry',
          name: 'Select entry…',
          type: 'flutter',
          isAction: true,
        ),
      ],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    platform.emitActions(platform.actions);
    await tester.pump();

    final buttonFinder = find.byKey(const Key('run-config-dropdown'));
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget(buttonFinder) as PopupMenuButton;
    final items = button.itemBuilder(tester.element(buttonFinder));
    expect(items, hasLength(2));
  });

  testWidgets('dropdown lists recommendations as suggested entries', (
    tester,
  ) async {
    final recommendation = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'flutter',
        name: 'Flutter',
        type: 'flutter',
        extras: {'device': 'linux'},
      ),
    );
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
      recommendations: [recommendation],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    final buttonFinder = find.byKey(const Key('run-config-dropdown'));
    final button = tester.widget(buttonFinder) as PopupMenuButton;
    final items = button.itemBuilder(tester.element(buttonFinder));
    expect(items, hasLength(2));
    final recommendationItem = items.whereType<PopupMenuItem>().last;
    final label = recommendationItem.child! as Text;
    expect(label.data, 'Flutter (Suggested)');
  });

  testWidgets('choosing isAction calls configureAction via picker', (
    tester,
  ) async {
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
      actions: const [
        LaunchAdapterConfigurationEntry(
          id: 'pick-entry',
          name: 'Select entry…',
          type: 'flutter',
          isAction: true,
        ),
      ],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(
      _host(
        cubit: cubit,
        pickActionResult: (_) async => {'path': '/entry.dart'},
      ),
    );
    platform.emitActions(platform.actions);
    await tester.pump();

    final buttonFinder = find.byKey(const Key('run-config-dropdown'));
    final button = tester.widget(buttonFinder) as PopupMenuButton;
    final items = button.itemBuilder(tester.element(buttonFinder));
    final actionItem = items.whereType<PopupMenuItem>().last;
    // Bypass generic variance: PopupMenuButton<_DropdownEntry>.onSelected.
    (button as dynamic).onSelected(actionItem.value);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.configureActionCalls, 1);
    expect(platform.lastConfigureActionId, 'pick-entry');
  });

  testWidgets('inline choice option calls setOption', (tester) async {
    final platform = _RecordingPlatform(
      configurations: [
        OwnedLaunchConfiguration(
          owner: _folder,
          configuration: const LaunchConfiguration(
            id: 'app',
            name: 'App',
            type: 'flutter',
          ),
        ),
      ],
      options: const [
        LaunchOption(
          id: 'device',
          label: 'Device',
          type: LaunchOptionType.choice,
          value: 'linux',
          choices: [
            LaunchOptionChoice(value: 'linux', label: 'Linux'),
            LaunchOptionChoice(value: 'chrome', label: 'Chrome'),
          ],
        ),
      ],
    );
    final cubit = _RecordingCubit(
      platform: platform,
      folders: const [_folder],
    );
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    cubit.setOption('device', 'chrome');
    await tester.pump();

    expect(cubit.setOptionCalls.last.key, 'device');
    expect(cubit.setOptionCalls.last.value, 'chrome');
    expect(find.text('Linux'), findsOneWidget);
  });

  testWidgets('Run button calls runSelected', (tester) async {
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.runSelectedCalls, 1);
    expect(cubit.state.sessions, isNotEmpty);
  });
}
