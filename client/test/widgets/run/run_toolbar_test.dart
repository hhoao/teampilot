import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_platform.dart';
import 'package:teampilot/services/run/run_session_manager.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/menu/sidebar_action_menu.dart';
import 'package:teampilot/widgets/run/run_config_editor_dialog.dart';
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
    this.compounds = const [],
    this.actions = const [],
    this.options = const [],
    this.recommendations = const [],
    List<String> Function(OwnedLaunchConfiguration owned)? validate,
    Map<String, List<String>>? kindsByType,
  }) : _validate = validate ?? ((_) => const []),
       _kindsByType = kindsByType ?? const {},
       sessionManager = RunSessionManager(
         executor: _FakeProcessLauncher(),
         adapters: _FakeAdapterLauncher(),
       );

  final List<OwnedLaunchConfiguration> configurations;
  final List<OwnedLaunchCompound> compounds;
  final List<LaunchAdapterConfigurationEntry> actions;
  final List<LaunchOption> options;
  final List<OwnedLaunchConfiguration> recommendations;
  final List<String> Function(OwnedLaunchConfiguration owned) _validate;
  final Map<String, List<String>> _kindsByType;

  @override
  final RunSessionManager sessionManager;

  var runSelectedCalls = 0;
  var configureActionCalls = 0;
  var deleteConfigurationCalls = 0;
  String? lastConfigureActionId;
  String? lastDeletedId;

  final _actionsController =
      StreamController<List<LaunchAdapterConfigurationEntry>>.broadcast();

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
      _validate(owned);

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) async {
    runSelectedCalls++;
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
  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  }) async {
    deleteConfigurationCalls++;
    lastDeletedId = id;
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
  }) async => recommendations;

  @override
  bool isTypeAvailable(String type, {required String targetId}) => true;

  @override
  String? unavailableReason(String type, {required String targetId}) => null;

  @override
  Map<String, Object?>? configurationSchema(String type) => null;

  @override
  List<String> kindsFor(String type) =>
      List<String>.from(_kindsByType[type] ?? const ['run']);

  @override
  List<LaunchTypeContribution> get launchTypes => const [];
}

class _RecordingCubit extends RunCubit {
  _RecordingCubit({required super.platform, required super.folders});

  final setOptionCalls = <MapEntry<String, Object?>>[];
  var acceptRecommendationCalls = 0;
  var deleteConfigurationCalls = 0;

  @override
  void setOption(String id, Object? value) {
    setOptionCalls.add(MapEntry(id, value));
    super.setOption(id, value);
  }

  @override
  Future<void> acceptRecommendation(
    OwnedLaunchConfiguration recommendation,
  ) async {
    acceptRecommendationCalls++;
    await super.acceptRecommendation(recommendation);
  }

  @override
  Future<void> deleteConfiguration(OwnedLaunchConfiguration owned) async {
    deleteConfigurationCalls++;
    await super.deleteConfiguration(owned);
  }
}

Future<void> _openConfigDropdown(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('run-config-dropdown')));
  await tester.pumpAndSettle();
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

    expect(find.byKey(const Key('run-config-dropdown')), findsOneWidget);
    await _openConfigDropdown(tester);
    expect(find.text('API'), findsWidgets);
    expect(find.text('Select entry…'), findsOneWidget);
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

    await _openConfigDropdown(tester);
    expect(find.text('Flutter (Suggested)'), findsOneWidget);
  });

  testWidgets('config menu includes add footer', (tester) async {
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    expect(find.byKey(const Key('run-config-add')), findsOneWidget);
    expect(find.text('Configure launch configurations'), findsOneWidget);
  });

  testWidgets('configure launch items opens list dialog', (tester) async {
    final config = _processConfig();
    final platform = _RecordingPlatform(configurations: [config]);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    await tester.tap(find.byKey(const Key('run-config-add')));
    await tester.pumpAndSettle();

    expect(find.text('Configure launch configurations'), findsWidgets);
    expect(find.text('API'), findsWidgets);
    expect(find.byKey(const Key('run-configurations-add')), findsOneWidget);
  });

  testWidgets('edit opens editor dialog', (tester) async {
    final config = _processConfig();
    final platform = _RecordingPlatform(configurations: [config]);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    await tester.tap(
      find.byKey(Key('run-config-edit-${config.selectionKey}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit configuration'), findsOneWidget);
  });

  testWidgets('delete confirms and calls cubit.deleteConfiguration', (
    tester,
  ) async {
    final config = _processConfig();
    final platform = _RecordingPlatform(configurations: [config]);
    final cubit = _RecordingCubit(
      platform: platform,
      folders: const [_folder],
    );
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    await tester.tap(
      find.byKey(Key('run-config-delete-${config.selectionKey}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete configuration "API"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(cubit.deleteConfigurationCalls, 1);
    expect(platform.deleteConfigurationCalls, 1);
    expect(platform.lastDeletedId, 'api');
  });

  testWidgets('edit and delete taps do not change selection', (tester) async {
    final api = _processConfig(id: 'api', name: 'API');
    final web = _processConfig(id: 'web', name: 'Web');
    final platform = _RecordingPlatform(configurations: [api, web]);
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await cubit.select(api.selectionKey);
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    await tester.tap(find.byKey(Key('run-config-edit-${web.selectionKey}')));
    await tester.pumpAndSettle();
    expect(cubit.state.selectedKey, api.selectionKey);

    await tester.ensureVisible(find.byKey(const Key('run-config-editor-cancel')));
    await tester.tap(find.byKey(const Key('run-config-editor-cancel')));
    await tester.pumpAndSettle();

    await _openConfigDropdown(tester);
    await tester.tap(find.byKey(Key('run-config-delete-${web.selectionKey}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(cubit.state.selectedKey, api.selectionKey);
  });

  testWidgets('recommendation edit opens editor without acceptRecommendation', (
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
    final cubit = _RecordingCubit(
      platform: platform,
      folders: const [_folder],
    );
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    expect(
      find.byKey(Key('run-config-delete-${recommendation.selectionKey}')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(Key('run-config-edit-${recommendation.selectionKey}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit configuration'), findsOneWidget);
    expect(cubit.acceptRecommendationCalls, 0);
  });

  testWidgets('compound rows have no edit or delete', (tester) async {
    final compound = OwnedLaunchCompound(
      owner: _folder,
      compound: const LaunchCompound(
        id: 'all',
        name: 'All services',
        configurationIds: ['api'],
      ),
    );
    final platform = _RecordingPlatform(
      configurations: [_processConfig()],
      compounds: [compound],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    expect(
      find.byKey(Key('run-config-edit-${compound.selectionKey}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('run-config-delete-${compound.selectionKey}')),
      findsNothing,
    );
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

    await _openConfigDropdown(tester);
    await tester.tap(find.text('Select entry…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.configureActionCalls, 1);
    expect(platform.lastConfigureActionId, 'pick-entry');
  });

  testWidgets('does not show build debug or more by default', (tester) async {
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

    expect(find.byKey(const Key('run-toolbar-build')), findsNothing);
    expect(find.byKey(const Key('run-toolbar-debug')), findsNothing);
    expect(find.byKey(const Key('run-toolbar-more')), findsNothing);
    expect(find.byKey(const Key('run-toolbar-run')), findsOneWidget);
  });

  testWidgets('choice option appears as compact selector', (tester) async {
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

    final optionFinder = find.byKey(const Key('run-toolbar-option-device'));
    expect(optionFinder, findsOneWidget);
    expect(find.byKey(const Key('run-toolbar-more')), findsNothing);

    final button = tester.widget<SidebarActionMenuButton>(optionFinder);
    final chrome = button.specs.where((s) => !s.isDivider).last;
    expect(chrome.label, 'Chrome');
    button.onSelected(chrome.value);
    await tester.pump();

    expect(cubit.setOptionCalls.last.key, 'device');
    expect(cubit.setOptionCalls.last.value, 'chrome');
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

    await tester.tap(find.byKey(const Key('run-toolbar-run')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.runSelectedCalls, 1);
    expect(cubit.state.sessions, isNotEmpty);
  });

  testWidgets(
    'schema validation failure dialog offers Edit configuration',
    (tester) async {
      final invalid = OwnedLaunchConfiguration(
        owner: _folder,
        configuration: const LaunchConfiguration(
          id: 'bad',
          name: 'Bad',
          type: 'process',
          command: '',
        ),
      );
      final platform = _RecordingPlatform(
        configurations: [invalid],
        validate: (_) => const ['command is required'],
      );
      final cubit = RunCubit(platform: platform, folders: const [_folder]);
      addTearDown(cubit.close);
      addTearDown(platform._actionsController.close);

      await cubit.load();
      await cubit.select(invalid.selectionKey);
      await tester.pumpWidget(_host(cubit: cubit));
      await tester.pump();

      await tester.tap(find.byKey(const Key('run-toolbar-run')));
      await tester.pumpAndSettle();

      expect(platform.runSelectedCalls, 0);
      expect(find.text('Command is required'), findsOneWidget);
      expect(find.text('Edit configuration'), findsWidgets);
      expect(find.textContaining('launch.json'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Edit configuration'));
      await tester.pumpAndSettle();

      expect(find.byType(RunConfigEditorDialog), findsOneWidget);
    },
  );

  testWidgets('debug kind shows debug glyph via kindsFor', (tester) async {
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
      kindsByType: const {
        'flutter': ['run', 'debug'],
      },
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await cubit.select(platform.configurations.single.selectionKey);
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    expect(find.byKey(const Key('run-toolbar-debug')), findsOneWidget);
    expect(find.byKey(const Key('run-toolbar-build')), findsNothing);
  });

  testWidgets('dropdown lists compounds and Run starts compound', (
    tester,
  ) async {
    final compound = OwnedLaunchCompound(
      owner: _folder,
      compound: const LaunchCompound(
        id: 'all',
        name: 'All services',
        configurationIds: ['api', 'web'],
      ),
    );
    final platform = _RecordingPlatform(
      configurations: [
        _processConfig(id: 'api', name: 'API'),
        _processConfig(id: 'web', name: 'Web'),
      ],
      compounds: [compound],
    );
    final cubit = RunCubit(platform: platform, folders: const [_folder]);
    addTearDown(cubit.close);
    addTearDown(platform._actionsController.close);

    await cubit.load();
    await cubit.select(compound.selectionKey);
    await tester.pumpWidget(_host(cubit: cubit));
    await tester.pump();

    await _openConfigDropdown(tester);
    expect(find.text('All services (compound)'), findsWidgets);
    // Close menu before tapping Run.
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('run-toolbar-run')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cubit.state.sessions, hasLength(2));
    expect(
      cubit.state.sessions.every((s) => s.compoundId == compound.compoundId),
      isTrue,
    );
  });
}
