import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../support/automation_test_fixtures.dart';
import '../../support/desktop_app_harness.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/stub_member_roster_service.dart';

const _testPresetId = 'preset-test';

class _FakeExpertHubSource extends CompositeExpertHubSource {
  _FakeExpertHubSource()
    : super(builtIns: const [], registry: _EmptyRegistry());

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => const [];
}

class _EmptyRegistry implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) =>
      Future.value(const []);

  @override
  Future<List<String>> categories({bool forceRefresh = false}) =>
      Future.value(const []);
}

ChatCubit _chatCubitWithWorkspace() {
  final cubit = testChatCubit(executableResolver: () => 'claude');
  cubit.applyState(
    ChatState(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

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

LaunchProfileCubit _emptyLaunchProfileCubit() {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('automation_editor_empty_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  cubit.applyState(const LaunchProfileState(isLoading: false));
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

ExpertHubCubit _expertHubCubit() => ExpertHubCubit(
  source: _FakeExpertHubSource(),
  loadFavorites: () async => const {},
  saveFavoriteToggle: (_) async => true,
  memberRosterService: stubMemberRosterService(),
  launchProfiles: () => throw UnimplementedError('not used'),
);

Widget _host({
  required AutomationCubit cubit,
  required Widget child,
  LaunchProfileCubit? launchProfileCubit,
  CliPresetsCubit? cliPresetsCubit,
  ExpertHubCubit? expertHubCubit,
  ChatCubit? chatCubit,
  SessionPreferencesCubit? sessionPreferencesCubit,
}) {
  final resolvedChat = chatCubit ?? _chatCubitWithWorkspace();
  final providers = <BlocProvider>[
    BlocProvider<AutomationCubit>.value(value: cubit),
    BlocProvider<ChatCubit>.value(value: resolvedChat),
    BlocProvider<ExpertHubCubit>.value(
      value: expertHubCubit ?? _expertHubCubit(),
    ),
    BlocProvider<LaunchProfileCubit>.value(
      value: launchProfileCubit ?? _emptyLaunchProfileCubit(),
    ),
  ];
  if (sessionPreferencesCubit != null) {
    providers.add(
      BlocProvider<SessionPreferencesCubit>.value(
        value: sessionPreferencesCubit,
      ),
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
    expect(find.text(l10n.automationsLaunchMode), findsNothing);
  });

  testWidgets('simple launch prompt shows landing-aligned fields', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithWorkspace();
    final cliPresetsCubit = _cliPresetsCubitWithPreset();
    final sessionPreferencesCubit = (await tester.runAsync(
      testSessionPreferencesCubit,
    ))!;
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);
    addTearDown(sessionPreferencesCubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        chatCubit: chatCubit,
        cliPresetsCubit: cliPresetsCubit,
        sessionPreferencesCubit: sessionPreferencesCubit,
        child: const AutomationEditorDialog(workspaceId: 'ws1'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCreateTitle), findsOneWidget);
    expect(find.text(l10n.automationsLaunchMode), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsOneWidget);
    expect(find.text(l10n.hubPublishKindExpert), findsOneWidget);
    expect(find.text(l10n.automationsPermissions), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byType(TpSelect<LaunchSecurityPolicy>));
    await tester.pumpAndSettle();
    expect(find.text(l10n.automationsPermissionsAskReadOnly), findsOneWidget);
    await tester.tap(find.text(l10n.automationsPermissionsAskReadOnly));
    await tester.pumpAndSettle();
    expect(find.text(l10n.automationsPermissionsAskReadOnly), findsOneWidget);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
  });

  testWidgets('team launch prompt shows team member picker', (tester) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithWorkspace();
    final launchProfileCubit = _teamLaunchProfileCubit();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(launchProfileCubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        chatCubit: chatCubit,
        launchProfileCubit: launchProfileCubit,
        child: AutomationEditorDialog(
          workspaceId: 'ws1',
          initial: sampleAutomation(
            id: 'edit-team',
            workspaceId: 'ws1',
            isPersonal: false,
            teamId: 'team-1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsEditTitle), findsOneWidget);
    expect(find.text(l10n.automationsTargetMember), findsOneWidget);
    expect(find.text('Lead'), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsNothing);
    expect(find.text(l10n.hubPublishKindExpert), findsNothing);
  });

  testWidgets('automation policy field key preserves intermediate dimensions', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithWorkspace();
    final cliPresetsCubit = _cliPresetsCubitWithPreset();
    final sessionPreferencesCubit = (await tester.runAsync(
      testSessionPreferencesCubit,
    ))!;
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);
    addTearDown(sessionPreferencesCubit.close);

    const policy = LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.ask,
      sandbox: LaunchSandboxPolicy.readOnly,
      hookTrust: LaunchHookTrustPolicy.trustedOnly,
    );
    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        chatCubit: chatCubit,
        cliPresetsCubit: cliPresetsCubit,
        sessionPreferencesCubit: sessionPreferencesCubit,
        child: AutomationEditorDialog(
          workspaceId: 'ws1',
          initial: sampleAutomation(
            id: 'intermediate-policy',
            workspaceId: 'ws1',
          ).copyWith(launchSecurityPolicy: policy),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('permissions-ask-readOnly-trustedOnly')),
      findsOneWidget,
    );
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

  testWidgets('empty message save shows TpForm field validation', (
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

    expect(find.byType(TpForm), findsOneWidget);

    await tester.tap(find.text(l10n.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.automationsValidationRequired), findsWidgets);
    expect(setup.cubit.state.automations, isEmpty);
  });
}
