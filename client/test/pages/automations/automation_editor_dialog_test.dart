import 'package:teampilot/models/automation_tab_scope.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _testPresetId = 'preset-test';

CliPresetsCubit _cliPresetsCubitWithPreset() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    CliPresetsState(
      status: CliPresetsLoadStatus.ready,
      presets: [
        CliPreset(
          id: _testPresetId,
          name: 'Default',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

LaunchProfileCubit _personalLaunchProfileCubit() {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      // In-memory path; no load() — state is seeded via applyState.
      Directory.systemTemp.createTempSync('automation_editor_personal_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  cubit.applyState(
    LaunchProfileState(
      isLoading: false,
      identities: [
        
      ],
    ),
  );
  return cubit;
}

LaunchProfileCubit _teamLaunchProfileCubit() {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('automation_editor_team_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  cubit.applyState(
    const LaunchProfileState(
      isLoading: false,
      identities: [
        TeamProfile(
          id: 'team-1',
          name: 'Team',
          members: [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'worker', name: 'Worker'),
          ],
        ),
      ],
      selectedTeamId: 'team-1',
    ),
  );
  return cubit;
}

Widget _host({
  required AutomationCubit cubit,
  required Widget child,
  LaunchProfileCubit? launchProfileCubit,
  CliPresetsCubit? cliPresetsCubit,
}) {
  final providers = <BlocProvider>[
    BlocProvider<AutomationCubit>.value(value: cubit),
  ];
  if (launchProfileCubit != null) {
    providers.add(
      BlocProvider<LaunchProfileCubit>.value(value: launchProfileCubit),
    );
  }
  if (cliPresetsCubit != null) {
    providers.add(BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit));
  }

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MultiBlocProvider(
        providers: providers,
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('scheduled message editor shows core fields only', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          launchProfileId: AutomationTabScope.simpleLaunchProfileId,
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCompactTitle), findsOneWidget);
    expect(find.text(l10n.automationsName), findsOneWidget);
    expect(find.text(l10n.automationsMessage), findsOneWidget);
    expect(find.text(l10n.automationsEnabled), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsNothing);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
  });

  testWidgets('personal launch prompt shows preset picker only', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final launchProfileCubit = _personalLaunchProfileCubit();
    final cliPresetsCubit = _cliPresetsCubitWithPreset();
    addTearDown(setup.cubit.close);
    addTearDown(launchProfileCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        launchProfileCubit: launchProfileCubit,
        cliPresetsCubit: cliPresetsCubit,
        child: AutomationEditorDialog(
          workspaceId: 'ws1',
          launchProfileId: AutomationTabScope.simpleLaunchProfileId,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCreateTitle), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsOneWidget);
    expect(find.text(l10n.automationsCli), findsNothing);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('team launch prompt shows member picker not cli', (tester) async {
    final setup = testAutomationSetup();
    final launchProfileCubit = _teamLaunchProfileCubit();
    addTearDown(setup.cubit.close);
    addTearDown(launchProfileCubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        launchProfileCubit: launchProfileCubit,
        child: const AutomationEditorDialog(
          workspaceId: 'ws1',
          launchProfileId: 'team-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCreateTitle), findsOneWidget);
    expect(find.text(l10n.automationsTargetMember), findsOneWidget);
    expect(find.text('Lead'), findsOneWidget);
    expect(find.text(l10n.automationsCli), findsNothing);
    expect(find.text(l10n.presetPickerTitle), findsNothing);
  });

  testWidgets('scheduled message editor pre-fills session defaults', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          launchProfileId: AutomationTabScope.simpleLaunchProfileId,
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Daily ping');
  });
}
