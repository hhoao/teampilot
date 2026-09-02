import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/services/automation/automation_schedule_defaults.dart';
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

  testWidgets('create dialog defaults to once mode and hides run limit', (
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

    final segmented = tester.widget<TpSegmentedPicker<AutomationScheduleMode>>(
      find.byType(TpSegmentedPicker<AutomationScheduleMode>),
    );
    expect(segmented.selected, AutomationScheduleMode.once);
    expect(find.byType(TpDatePicker), findsOneWidget);
    expect(find.byType(TpTimePicker), findsOneWidget);
    expect(find.text(l10n.automationsMaxRunCount), findsNothing);
  });

  testWidgets(
    'saving a once draft stores runAtMs with an implicit limit of 1',
    (tester) async {
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

      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.enterText(find.byType(TpTextarea), 'ping');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text(l10nOfDialog(tester).save));
        await pumpUntilClosed(tester);
      });

      expect(setup.cubit.state.automations, hasLength(1));
      final saved = setup.cubit.state.automations.single;
      expect(saved.preset, AutomationSchedulePreset.once);
      expect(saved.runAtMs, isNotNull);
      expect(
        saved.runAtMs!,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      expect(saved.maxRunCount, 1);
      expect(saved.dtstartMs, saved.runAtMs);
      expect(saved.enabled, isTrue);
      expect(saved.nextRunAtMs, saved.runAtMs);
    },
  );

  testWidgets('countdown save composes now plus the delay', (tester) async {
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

    final l10n = l10nOfDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.enterText(find.byType(TpTextarea), 'ping');
    await tester.tap(find.text(l10n.automationsScheduleModeCountdown));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final before = DateTime.now();
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.save));
      await pumpUntilClosed(tester);
    });
    final after = DateTime.now();

    expect(setup.cubit.state.automations, hasLength(1));
    final saved = setup.cubit.state.automations.single;
    expect(saved.preset, AutomationSchedulePreset.once);
    expect(saved.maxRunCount, 1);
    expect(saved.dtstartMs, saved.runAtMs);
    // Default chip is 15 minutes; the saved target must land between the
    // pre-save and post-save wall clocks plus the delay.
    expect(
      saved.runAtMs,
      inInclusiveRange(
        before.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
        after.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
      ),
    );
  });

  testWidgets('run limit field shows for recurring and stays hidden for once', (
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

    final l10n = l10nOfDialog(tester);
    expect(find.text(l10n.automationsMaxRunCount), findsNothing);

    await tester.tap(find.text(l10n.automationsScheduleModeRecurring));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.automationsMaxRunCount), findsOneWidget);
  });

  testWidgets('saving an expired once automation unchanged is rejected', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    await tester.runAsync(() async {
      await setup.cubit.loadForWorkspace('ws1');
      // Seed through the cubit so the fixture matches real app state: an
      // expired once schedule is disabled on save (Task 4 semantics).
      await setup.cubit.save(
        sampleAutomation(
          id: 'expired',
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          preset: AutomationSchedulePreset.once,
          runAtMs: DateTime.now()
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
      );
    });
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          initial: setup.cubit.state.automations
              .where((a) => a.id == 'expired')
              .first,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = l10nOfDialog(tester);

    await tester.enterText(find.byType(TpTextarea), 'ping');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.save));
      await drainPendingAsyncWork();
    });
    await tester.pump();

    // Unchanged expired target: the stored ms round-trips, the save is
    // rejected, and the dialog stays open on the once time field.
    expect(find.text(l10n.automationsSchedulePastTime), findsOneWidget);
    expect(
      setup.cubit.state.automations.where((a) => a.id == 'expired').single,
      isA<Automation>()
          .having((a) => a.enabled, 'enabled', false)
          .having((a) => a.message, 'message', 'hello'),
    );
  });

  testWidgets('changing the time on an expired once automation re-runs it', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final initialRunAt = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await setup.cubit.loadForWorkspace('ws1');
      // Seed through the cubit for real app state: expired once, disabled,
      // with a run already counted against it.
      await setup.cubit.save(
        sampleAutomation(
          id: 'expired-rerun',
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          preset: AutomationSchedulePreset.once,
          runAtMs: initialRunAt,
        ).copyWith(runCount: 1),
      );
      await setup.cubit.toggleEnabled('ws1', 'expired-rerun');
    });
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          initial: setup.cubit.state.automations
              .where((a) => a.id == 'expired-rerun')
              .first,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = l10nOfDialog(tester);

    // Re-arm the automation in the UI: move the target well into the future
    // first (23:59 today; the wall clock is at least two hours before that
    // because the stored target was now-2h). The run-limit lock applies to
    // the unchanged expired target, so the enabled switch only becomes
    // operable once the schedule is re-armed; flip it back on afterwards.
    await tester.enterText(find.byKey(const Key('tp-time-picker-hour')), '23');
    await tester.enterText(
      find.byKey(const Key('tp-time-picker-minute')),
      '59',
    );
    await tester.pump();
    final enabledSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(enabledSwitch).onChanged, isNotNull);
    await tester.tap(enabledSwitch);
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.save));
      await pumpUntilClosed(tester);
    });

    final saved = setup.cubit.state.automations
        .where((a) => a.id == 'expired-rerun')
        .single;
    expect(saved.runAtMs, isNot(initialRunAt));
    expect(saved.runAtMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
    // Time changed on a once schedule → runCount resets so it can fire again.
    expect(saved.runCount, 0);
    expect(saved.enabled, isTrue);
    expect(saved.maxRunCount, 1);
  });

  testWidgets(
    're-arming a fired once automation with an implicit run limit re-enables it',
    (tester) async {
      final setup = testAutomationSetup();
      final initialRunAt = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      await tester.runAsync(() async {
        await setup.cubit.loadForWorkspace('ws1');
        // Seed through the cubit for real app state: the automation already
        // fired, so it carries maxRunCount 1 with runCount 1 and was disabled
        // by the run-limit rule on save.
        await setup.cubit.save(
          sampleAutomation(
            id: 'fired-limit',
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            preset: AutomationSchedulePreset.once,
            runAtMs: initialRunAt,
          ).copyWith(maxRunCount: 1, runCount: 1, enabled: false),
        );
      });
      addTearDown(setup.cubit.close);

      await tester.pumpWidget(
        _host(
          cubit: setup.cubit,
          child: AutomationEditorDialog(
            kind: AutomationEditorKind.scheduledMessage,
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            initial: setup.cubit.state.automations
                .where((a) => a.id == 'fired-limit')
                .first,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n = l10nOfDialog(tester);

      // The enabled switch is locked while the unchanged target is expired,
      // and must become operable once the schedule is re-armed: the run
      // limit applies to the runCount the automation will save with, and
      // changing the target zeroes it.
      await tester.enterText(
        find.byKey(const Key('tp-time-picker-hour')),
        '23',
      );
      await tester.enterText(
        find.byKey(const Key('tp-time-picker-minute')),
        '59',
      );
      await tester.pump();
      final enabledSwitch = find.byType(Switch).first;
      expect(tester.widget<Switch>(enabledSwitch).onChanged, isNotNull);
      await tester.tap(enabledSwitch);
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.save));
        await pumpUntilClosed(tester);
      });

      final saved = setup.cubit.state.automations
          .where((a) => a.id == 'fired-limit')
          .single;
      expect(saved.preset, AutomationSchedulePreset.once);
      expect(saved.runAtMs, isNot(initialRunAt));
      expect(saved.runAtMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
      expect(saved.maxRunCount, 1);
      expect(saved.runCount, 0);
      expect(saved.enabled, isTrue);
    },
  );

  testWidgets(
    'converting a fired recurring automation to once resets its run count',
    (tester) async {
      final setup = testAutomationSetup();
      await tester.runAsync(() async {
        await setup.cubit.loadForWorkspace('ws1');
        // Seed through the cubit for real app state: a daily automation that
        // already accumulated runs. Its timezone is the device zone so the
        // once slot the picker seeds (now + 15 minutes) composes into the
        // future whatever the host offset is.
        await setup.cubit.save(
          sampleAutomation(
            id: 'recurring-to-once',
            workspaceId: 'ws1',
            sessionId: 'sess-1',
          ).copyWith(runCount: 3, timezone: resolveDeviceTimezoneIdentifier()),
        );
      });
      addTearDown(setup.cubit.close);

      await tester.pumpWidget(
        _host(
          cubit: setup.cubit,
          child: AutomationEditorDialog(
            kind: AutomationEditorKind.scheduledMessage,
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            initial: setup.cubit.state.automations
                .where((a) => a.id == 'recurring-to-once')
                .first,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n = l10nOfDialog(tester);

      await tester.tap(find.text(l10n.automationsScheduleModeOnce));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.enterText(find.byType(TpTextarea), 'ping');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.save));
        await pumpUntilClosed(tester);
      });

      final saved = setup.cubit.state.automations
          .where((a) => a.id == 'recurring-to-once')
          .single;
      expect(saved.preset, AutomationSchedulePreset.once);
      expect(saved.runAtMs, isNotNull);
      expect(
        saved.runAtMs!,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      // The stale recurring run count must not leak into the once schedule —
      // against the implicit limit of 1 it would disable it on save forever.
      expect(saved.runCount, 0);
      expect(saved.maxRunCount, 1);
      expect(saved.enabled, isTrue);
    },
  );

  testWidgets('converting once back to recurring clears the one-shot target', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final seededRunAt = DateTime.now()
        .add(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await setup.cubit.loadForWorkspace('ws1');
      // Seed through the cubit for real app state: a once schedule that
      // already fired and was retired by its implicit limit, still carrying
      // a future target.
      await setup.cubit.save(
        sampleAutomation(
          id: 'once-to-recurring',
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          preset: AutomationSchedulePreset.once,
          runAtMs: seededRunAt,
        ).copyWith(runCount: 1, dtstartMs: seededRunAt),
      );
    });
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          initial: setup.cubit.state.automations
              .where((a) => a.id == 'once-to-recurring')
              .first,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = l10nOfDialog(tester);

    // Converting to recurring releases the once limit lock (the run-limit
    // field is empty in recurring mode), so the switch is operable again.
    await tester.tap(find.text(l10n.automationsScheduleModeRecurring));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final enabledSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(enabledSwitch).onChanged, isNotNull);
    await tester.tap(enabledSwitch);
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.save));
      await pumpUntilClosed(tester);
    });

    final saved = setup.cubit.state.automations
        .where((a) => a.id == 'once-to-recurring')
        .single;
    expect(saved.preset, AutomationSchedulePreset.daily);
    // The one-shot target is gone (toJson omits a null runAtMs).
    expect(saved.runAtMs, isNull);
    expect(saved.dtstartMs, seededRunAt);
    // Converting does not reset the run count — only a changed once target
    // does.
    expect(saved.runCount, 1);
    expect(saved.enabled, isTrue);
  });

  testWidgets(
    'fired once automation with unchanged target keeps its limit lock',
    (tester) async {
      final setup = testAutomationSetup();
      final initialRunAt = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      await tester.runAsync(() async {
        await setup.cubit.loadForWorkspace('ws1');
        await setup.cubit.save(
          sampleAutomation(
            id: 'fired-stale',
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            preset: AutomationSchedulePreset.once,
            runAtMs: initialRunAt,
          ).copyWith(maxRunCount: 1, runCount: 1, enabled: false),
        );
      });
      addTearDown(setup.cubit.close);

      await tester.pumpWidget(
        _host(
          cubit: setup.cubit,
          child: AutomationEditorDialog(
            kind: AutomationEditorKind.scheduledMessage,
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            initial: setup.cubit.state.automations
                .where((a) => a.id == 'fired-stale')
                .first,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Unchanged expired target: the limit still applies to the stored
      // runCount, so the switch stays locked off.
      final enabledSwitch = find.byType(Switch).first;
      expect(tester.widget<Switch>(enabledSwitch).onChanged, isNull);
      expect(setup.cubit.state.automations.length, 1);
    },
  );

  testWidgets(
    'past-time error clears when the target is moved into the future',
    (tester) async {
      final setup = testAutomationSetup();
      await tester.runAsync(() async {
        await setup.cubit.loadForWorkspace('ws1');
        await setup.cubit.save(
          sampleAutomation(
            id: 'stale-error',
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            preset: AutomationSchedulePreset.once,
            runAtMs: DateTime.now()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch,
          ),
        );
      });
      addTearDown(setup.cubit.close);

      await tester.pumpWidget(
        _host(
          cubit: setup.cubit,
          child: AutomationEditorDialog(
            kind: AutomationEditorKind.scheduledMessage,
            workspaceId: 'ws1',
            sessionId: 'sess-1',
            initial: setup.cubit.state.automations
                .where((a) => a.id == 'stale-error')
                .first,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n = l10nOfDialog(tester);

      // First save with the unchanged expired target: rejected with the
      // past-time error on the once time field.
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.save));
        await drainPendingAsyncWork();
      });
      await tester.pump();
      expect(find.text(l10n.automationsSchedulePastTime), findsOneWidget);

      // Moving the target into the future must clear that stale error so the
      // next save validates and succeeds instead of being bricked. The
      // automation was disabled by the earlier expiry, so flip the (now
      // unlocked) switch back on too.
      await tester.enterText(
        find.byKey(const Key('tp-time-picker-hour')),
        '23',
      );
      await tester.enterText(
        find.byKey(const Key('tp-time-picker-minute')),
        '59',
      );
      await tester.pump();
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.save));
        await pumpUntilClosed(tester);
      });

      expect(find.byType(AutomationEditorDialog), findsNothing);
      expect(
        setup.cubit.state.automations
            .where((a) => a.id == 'stale-error')
            .single,
        isA<Automation>()
            .having(
              (a) => a.runAtMs,
              'runAtMs',
              greaterThan(DateTime.now().millisecondsSinceEpoch),
            )
            .having((a) => a.enabled, 'enabled', isTrue),
      );
    },
  );
}

AppLocalizations l10nOfDialog(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AutomationEditorDialog)));

/// Drains until the editor dialog pops after a successful save (the dialog
/// closes itself once [AutomationCubit.save] resolves; repository IO runs
/// outside the fake clock). A rejected save keeps the dialog open and the
/// deadline exhausts harmlessly.
Future<void> pumpUntilClosed(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (find.byType(AutomationEditorDialog).evaluate().isNotEmpty &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 10));
    await drainPendingAsyncWork();
  }
}
