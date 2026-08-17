import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit() {
    emit(const AppProviderState());
  }
}

const _team = TeamProfile(
  id: 'team-1',
  name: 'Alpha',
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    TeamMemberConfig(id: 'worker', name: 'Worker'),
  ],
);

final _workspace = Workspace(
  workspaceId: 'ws1',
  folders: const [WorkspaceFolder(path: '/repo')],
  createdAt: 1,
);

LaunchProfileCubit _launchCubitFor(TeamProfile team) {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('landing_team_settings_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  cubit.applyState(
    LaunchProfileState(
      isLoading: false,
      identities: [team],
      selectedTeamId: 'team-1',
    ),
  );
  return cubit;
}

LaunchProfileCubit _launchCubit() => _launchCubitFor(_team);

CliPresetsCubit _presetsCubit() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    const CliPresetsState(status: CliPresetsLoadStatus.ready, presets: []),
  );
  return cubit;
}

Widget _wrap({
  required Widget child,
  required LaunchProfileCubit launchCubit,
  required CliPresetsCubit presetsCubit,
  required AppProviderCubit providerCubit,
  required ChatCubit chatCubit,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MultiBlocProvider(
    providers: [
      BlocProvider<LaunchProfileCubit>.value(value: launchCubit),
      BlocProvider<CliPresetsCubit>.value(value: presetsCubit),
      BlocProvider<AppProviderCubit>.value(value: providerCubit),
      BlocProvider<ChatCubit>.value(value: chatCubit),
    ],
    child: CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: RepositoryProvider<SessionRepository>.value(
        value: SessionRepository(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
            child: child,
          ),
        ),
      ),
    ),
  );
}

Future<void> _openLandingSettings(
  WidgetTester tester, {
  required Size viewport,
  required LaunchProfileCubit launchCubit,
  required CliPresetsCubit presetsCubit,
  required AppProviderCubit providerCubit,
  required ChatCubit chatCubit,
  TeamProfile team = _team,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _wrap(
      launchCubit: launchCubit,
      presetsCubit: presetsCubit,
      providerCubit: providerCubit,
      chatCubit: chatCubit,
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              showLandingTeamSettingsDialog(
                context,
                workspace: _workspace,
                team: team,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('narrow: nav → detail → back via TpDialogNavShell', (
    tester,
  ) async {
    final launchCubit = _launchCubit();
    addTearDown(launchCubit.close);
    final presetsCubit = _presetsCubit();
    addTearDown(presetsCubit.close);
    final providerCubit = _SeededAppProviderCubit();
    addTearDown(providerCubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await _openLandingSettings(
      tester,
      viewport: const Size(400, 800),
      launchCubit: launchCubit,
      presetsCubit: presetsCubit,
      providerCubit: providerCubit,
      chatCubit: chatCubit,
    );

    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.byType(TpDialogNavShell), findsOneWidget);
    expect(find.text(l10n.teamSettings), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsNavTeam), findsOneWidget);
    expect(find.text(l10n.members), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsNavMachines), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    // Detail body not pushed yet on narrow.
    expect(find.text(l10n.landingTeamSettingsGlobalHint), findsNothing);

    await tester.tap(find.text(l10n.landingTeamSettingsNavTeam));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Nav route stays under detail in the nested Navigator, so two chevrons.
    expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
    expect(find.text(l10n.landingTeamSettingsGlobalHint), findsWidgets);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded).last);
    await tester.pump(); // start pop
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.teamSettings), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsGlobalHint), findsNothing);
  });

  testWidgets('wide: dual-pane nav and body visible together', (tester) async {
    final launchCubit = _launchCubit();
    addTearDown(launchCubit.close);
    final presetsCubit = _presetsCubit();
    addTearDown(presetsCubit.close);
    final providerCubit = _SeededAppProviderCubit();
    addTearDown(providerCubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await _openLandingSettings(
      tester,
      viewport: const Size(1200, 800),
      launchCubit: launchCubit,
      presetsCubit: presetsCubit,
      providerCubit: providerCubit,
      chatCubit: chatCubit,
    );

    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.byType(TpDialogNavShell), findsOneWidget);
    expect(find.text(l10n.teamSettings), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsNavTeam), findsWidgets);
    expect(find.text(l10n.members), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsNavMachines), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

    // Deferred mount + frame for pane host.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.landingTeamSettingsGlobalHint), findsWidgets);
  });

  testWidgets('escape dismisses the draft dialog', (tester) async {
    final launchCubit = _launchCubit();
    addTearDown(launchCubit.close);
    final presetsCubit = _presetsCubit();
    addTearDown(presetsCubit.close);
    final providerCubit = _SeededAppProviderCubit();
    addTearDown(providerCubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await _openLandingSettings(
      tester,
      viewport: const Size(1200, 800),
      launchCubit: launchCubit,
      presetsCubit: presetsCubit,
      providerCubit: providerCubit,
      chatCubit: chatCubit,
    );

    expect(find.byType(TpDialogNavShell), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TpDialogNavShell), findsNothing);
  });

  testWidgets('uses WorkspacePanePolicy narrow breakpoint', (tester) async {
    final launchCubit = _launchCubit();
    addTearDown(launchCubit.close);
    final presetsCubit = _presetsCubit();
    addTearDown(presetsCubit.close);
    final providerCubit = _SeededAppProviderCubit();
    addTearDown(providerCubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    final breakpoint = WorkspacePanePolicy.narrowBreakpointWidth;
    await _openLandingSettings(
      tester,
      viewport: Size(breakpoint - 1, 800),
      launchCubit: launchCubit,
      presetsCubit: presetsCubit,
      providerCubit: providerCubit,
      chatCubit: chatCubit,
    );

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.byType(TpDialogNavShell), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.text(l10n.landingTeamSettingsNavTeam), findsOneWidget);

    await tester.tap(find.text(l10n.landingTeamSettingsNavTeam));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
  });

  testWidgets(
    'turning off the landing member permission switch preserves an intermediate policy',
    (tester) async {
      const intermediate = LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.readOnly,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      );
      const team = TeamProfile(
        id: 'team-1',
        name: 'Alpha',
        members: [
          TeamMemberConfig(
            id: 'team-lead',
            name: 'Lead',
            launchSecurityPolicy: intermediate,
          ),
          TeamMemberConfig(id: 'worker', name: 'Worker'),
        ],
        roster: [
          TeamRosterSlot(
            id: 'team-lead',
            expertKey: 'teampilot/builtin/team-lead',
          ),
        ],
      );
      final launchCubit = _launchCubitFor(team);
      addTearDown(launchCubit.close);
      final presetsCubit = _presetsCubit();
      addTearDown(presetsCubit.close);
      final providerCubit = _SeededAppProviderCubit();
      addTearDown(providerCubit.close);
      final chatCubit = testChatCubit(executableResolver: () => 'claude');
      addTearDown(chatCubit.close);

      await _openLandingSettings(
        tester,
        viewport: const Size(400, 800),
        launchCubit: launchCubit,
        presetsCubit: presetsCubit,
        providerCubit: providerCubit,
        chatCubit: chatCubit,
        team: team,
      );

      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.members));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final permissionSwitch = tester.widget<Switch>(find.byType(Switch).first);
      permissionSwitch.onChanged!(false);
      await tester.pump();
      await tester.tap(find.text(l10n.save));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        launchCubit.state.selectedTeam?.members.first.launchSecurityPolicy,
        intermediate,
      );
    },
  );
}
