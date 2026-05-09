import 'dart:ui';

import 'package:flashskyai_client/app_keys.dart';
import 'package:flashskyai_client/chat_controller.dart';
import 'package:flashskyai_client/layout_controller.dart';
import 'package:flashskyai_client/layout_repository.dart';
import 'package:flashskyai_client/llm_config.dart';
import 'package:flashskyai_client/llm_config_controller.dart';
import 'package:flashskyai_client/main.dart';
import 'package:flashskyai_client/team_config.dart';
import 'package:flashskyai_client/team_controller.dart';
import 'package:flashskyai_client/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingClipboardWriter implements ClipboardWriter {
  final copied = <String>[];

  @override
  Future<void> setText(String text) async {
    copied.add(text);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<TeamController> createController({TeamLauncher? launcher}) async {
    final repository = TeamRepository(await SharedPreferences.getInstance());
    final controller = TeamController(
      repository: repository,
      launcher: launcher ?? (_, _) async {},
      currentDirectoryProvider: () => '/work/current',
    );
    await controller.load();
    return controller;
  }

  Future<LayoutController> createLayoutController() async {
    final controller = LayoutController(
      repository: LayoutRepository(await SharedPreferences.getInstance()),
    );
    await controller.load();
    return controller;
  }

  FlashskyAiClientApp createApp(
    TeamController controller, {
    LayoutController? layoutController,
    LlmConfigController? llmConfigController,
  }) {
    return FlashskyAiClientApp(
      controller: controller,
      chatController: ChatController(clipboard: RecordingClipboardWriter()),
      layoutController: layoutController,
      llmConfigController: llmConfigController,
    );
  }

  Future<void> pumpDesktopApp(
    WidgetTester tester,
    TeamController controller, {
    LayoutController? layoutController,
    LlmConfigController? llmConfigController,
  }) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      createApp(
        controller,
        layoutController: layoutController,
        llmConfigController: llmConfigController,
      ),
    );
  }

  LlmConfigController createLlmController() {
    return LlmConfigController(
      initialConfig: const LlmConfig(
        providers: {
          'OpenRoute': LlmProviderConfig(
            name: 'OpenRoute',
            type: 'api',
            providerType: 'openai',
            baseUrl: 'https://openrouter.ai/api/v1/',
            apiKey: '',
          ),
          'DeepSeek': LlmProviderConfig(
            name: 'DeepSeek',
            type: 'api',
            providerType: 'openai',
            baseUrl: 'https://api.deepseek.com',
            apiKey: 'sk-secret',
          ),
        },
        models: {
          'openai/gpt-5.2': LlmModelConfig(
            id: 'openai/gpt-5.2',
            name: 'openai/gpt-5.2',
            provider: 'OpenRoute',
            model: 'openai/gpt-5.2',
            enabled: true,
          ),
          'ghost': LlmModelConfig(
            id: 'ghost',
            name: 'ghost',
            provider: 'Missing',
            model: 'ghost-model',
            enabled: true,
          ),
        },
      ),
    );
  }

  testWidgets('renders corrected chat workbench shell', (tester) async {
    final controller = await createController();

    await pumpDesktopApp(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.appRailChatButton), findsOneWidget);
    expect(find.byKey(AppKeys.contextSidebar), findsOneWidget);
    expect(find.byKey(AppKeys.workspaceTopbar), findsOneWidget);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
    expect(find.text('Default Team'), findsWidgets);
    expect(find.text('Team Sessions'), findsOneWidget);
    expect(find.text('Shell chat workbench'), findsWidgets);
    expect(find.text('team-lead'), findsWidgets);
  });

  testWidgets('config workspace uses full width without chat right tools', (
    tester,
  ) async {
    final controller = await createController();

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.configWorkspace), findsOneWidget);
    expect(find.text('Team Configuration'), findsWidgets);
    expect(find.byKey(AppKeys.rightToolsPanel), findsNothing);
  });

  testWidgets('team config saves selected team fields', (tester) async {
    final controller = await createController();

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.teamConfigWorkspace), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.teamNameField), 'agent');
    await tester.enterText(
      find.byKey(AppKeys.workingDirectoryField),
      '/work/agent',
    );
    await tester.enterText(
      find.byKey(AppKeys.extraArgsField),
      '--permission-mode acceptEdits',
    );
    await tester.tap(find.byKey(AppKeys.saveButton));
    await tester.pumpAndSettle();

    expect(controller.selectedTeam?.name, 'agent');
    expect(controller.selectedTeam?.workingDirectory, '/work/agent');
    expect(controller.selectedTeam?.extraArgs, '--permission-mode acceptEdits');
    expect(find.text('Saved agent.'), findsWidgets);
  });

  testWidgets('member config edits member launch fields and preview', (
    tester,
  ) async {
    final controller = await createController();
    final member = controller.selectedTeam!.members.single;

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.configMembersSectionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.memberConfigWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.memberConfigCommandPreview), findsOneWidget);

    await tester.enterText(
      find.byKey(AppKeys.memberProviderField(member.id)),
      'openai',
    );
    await tester.enterText(
      find.byKey(AppKeys.memberModelField(member.id)),
      'gpt-5.4',
    );
    await tester.enterText(
      find.byKey(AppKeys.memberAgentField(member.id)),
      'reviewer',
    );
    await tester.enterText(
      find.byKey(AppKeys.memberExtraArgsField(member.id)),
      '--fast',
    );
    await tester.tap(find.byKey(AppKeys.memberConfigSaveButton));
    await tester.pumpAndSettle();

    final updated = controller.selectedTeam!.members.single;
    expect(updated.provider, 'openai');
    expect(updated.model, 'gpt-5.4');
    expect(updated.agent, 'reviewer');
    expect(updated.extraArgs, '--fast');
    expect(find.textContaining('--provider openai'), findsOneWidget);
    expect(find.textContaining('--model gpt-5.4'), findsOneWidget);
  });

  testWidgets('member config guards team-lead rename', (tester) async {
    final controller = await createController();
    final member = controller.selectedTeam!.members.single;

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.configMembersSectionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(AppKeys.memberNameField(member.id)),
      'lead',
    );
    await tester.tap(find.byKey(AppKeys.memberConfigSaveButton));
    await tester.pumpAndSettle();

    expect(controller.selectedTeam!.members.single.name, 'team-lead');
    expect(find.byKey(AppKeys.memberConfigValidationMessage), findsOneWidget);
  });

  testWidgets('llm config renders providers models raw json and validation', (
    tester,
  ) async {
    final controller = await createController();
    final llmController = createLlmController();

    await pumpDesktopApp(
      tester,
      controller,
      llmConfigController: llmController,
    );
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.configLlmSectionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.llmConfigWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.llmValidationSummary), findsOneWidget);
    expect(find.text('OpenRoute'), findsWidgets);
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.textContaining('OpenRoute API key is empty.'), findsOneWidget);
    expect(
      find.textContaining('ghost references missing provider Missing.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppKeys.llmModelsTab));
    await tester.pumpAndSettle();
    expect(find.text('openai/gpt-5.2'), findsWidgets);
    expect(find.text('Missing'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.llmRawJsonTab));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.llmRawJsonPreview), findsOneWidget);
    expect(find.textContaining(LlmConfig.maskedSecret), findsWidgets);
    expect(find.textContaining('sk-secret'), findsNothing);
  });

  testWidgets('config toggles hide the file tree globally', (tester) async {
    final controller = await createController();
    final layoutController = await createLayoutController();

    await pumpDesktopApp(
      tester,
      controller,
      layoutController: layoutController,
    );
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.configLayoutSectionButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppKeys.fileTreeVisibilitySwitch));
    await tester.tap(find.byKey(AppKeys.fileTreeVisibilitySwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.appRailChatButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsNothing);
  });

  testWidgets('config can place tools in a bottom tray', (tester) async {
    final controller = await createController();
    final layoutController = await createLayoutController();

    await pumpDesktopApp(
      tester,
      controller,
      layoutController: layoutController,
    );
    await tester.tap(find.byKey(AppKeys.appRailConfigButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.configLayoutSectionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.toolPlacementBottomButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.appRailChatButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.rightToolsPanel), findsNothing);
    expect(find.byKey(AppKeys.bottomToolsPanel), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsOneWidget);
    expect(find.byKey(AppKeys.fileTreePanel), findsOneWidget);
  });

  testWidgets('dragged right tools width is persisted', (tester) async {
    final controller = await createController();
    final layoutController = await createLayoutController();

    await pumpDesktopApp(
      tester,
      controller,
      layoutController: layoutController,
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(AppKeys.rightToolsPanel)).width, 320);

    await tester.drag(
      find.byKey(AppKeys.rightToolsDivider),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();

    expect(layoutController.preferences.rightToolsWidth, greaterThan(320));

    final reloaded = await createLayoutController();
    await pumpDesktopApp(tester, controller, layoutController: reloaded);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(AppKeys.rightToolsPanel)).width,
      reloaded.preferences.rightToolsWidth,
    );
  });

  testWidgets('sending a prompt adds local user and system messages', (
    tester,
  ) async {
    final controller = await createController();

    await pumpDesktopApp(tester, controller);
    await tester.enterText(find.byKey(AppKeys.chatInput), 'Continue the plan');
    await tester.tap(find.byKey(AppKeys.sendPromptButton));
    await tester.pumpAndSettle();

    expect(find.text('Continue the plan'), findsOneWidget);
    expect(
      find.text(
        'Copied prompt for team-lead. Paste it into the FlashskyAI terminal.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting a member changes the composer target', (tester) async {
    final controller = await createController();
    await controller.addMember();
    final member = controller.selectedTeam!.members.last;

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.memberRow(member.id)));
    await tester.pumpAndSettle();

    expect(find.text('To: New Member'), findsOneWidget);
  });

  testWidgets('member open button launches one member from right panel', (
    tester,
  ) async {
    TeamMemberConfig? launchedMember;
    final controller = await createController(
      launcher: (_, member) async {
        launchedMember = member;
      },
    );
    final member = controller.selectedTeam!.members.single;

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.memberOpenButton(member.id)));
    await tester.pumpAndSettle();

    expect(launchedMember?.name, 'team-lead');
    expect(find.textContaining('Started team-lead:'), findsOneWidget);
  });

  testWidgets('open team button launches all members', (tester) async {
    final launched = <String>[];
    final controller = await createController(
      launcher: (_, member) async {
        launched.add(member.name);
      },
    );
    await controller.addMember();

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.openTeamButton));
    await tester.pumpAndSettle();

    expect(launched, ['team-lead', 'New Member']);
    expect(find.text('Started 2 members.'), findsOneWidget);
  });

  testWidgets('open team-lead shows local status when team-lead is missing', (
    tester,
  ) async {
    final controller = await createController();
    final selected = controller.selectedTeam!;
    await controller.updateSelected(
      selected.copyWith(
        members: const [TeamMemberConfig(id: 'coder', name: 'coder')],
      ),
    );

    await pumpDesktopApp(tester, controller);
    await tester.tap(find.byKey(AppKeys.openTeamLeadButton));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'FlashskyAI requires a member named team-lead before opening the team lead.',
      ),
      findsOneWidget,
    );
  });
}
