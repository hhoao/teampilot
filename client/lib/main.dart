import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controllers/chat_controller.dart';
import 'controllers/config_controller.dart';
import 'controllers/layout_controller.dart';
import 'controllers/llm_config_controller.dart';
import 'controllers/team_controller.dart';
import 'l10n/app_localizations.dart';
import 'models/layout_preferences.dart';
import 'models/team_config.dart';
import 'pages/chat_workbench.dart';
import 'pages/config_workspace.dart';
import 'pages/workspace_shell.dart';
import 'repositories/layout_repository.dart';
import 'repositories/llm_config_repository.dart';
import 'repositories/team_repository.dart';
import 'theme/app_theme.dart';
import 'utils/app_keys.dart';
import 'widgets/app_rail.dart';
import 'widgets/context_sidebar.dart';
import 'widgets/right_tools_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final controller = TeamController(repository: TeamRepository(preferences));
  final layoutController = LayoutController(
    repository: LayoutRepository(preferences),
  );
  final llmConfigController = LlmConfigController(
    repository: LlmConfigRepository(File('../flashshkyai/llm/llm_config.json')),
  );
  await controller.load();
  await layoutController.load();
  await llmConfigController.load();
  runApp(
    FlashskyAiClientApp(
      controller: controller,
      layoutController: layoutController,
      llmConfigController: llmConfigController,
    ),
  );
}

class FlashskyAiClientApp extends StatelessWidget {
  FlashskyAiClientApp({
    required this.controller,
    ChatController? chatController,
    ConfigController? configController,
    LlmConfigController? llmConfigController,
    this.layoutController,
    super.key,
  }) : chatController =
           chatController ?? ChatController(),
       configController = configController ?? ConfigController(),
       llmConfigController = llmConfigController ?? LlmConfigController();

  final TeamController controller;
  final ChatController chatController;
  final ConfigController configController;
  final LlmConfigController llmConfigController;
  final LayoutController? layoutController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FlashskyAI Teams',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (final supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) {
            return supportedLocale;
          }
        }
        return const Locale('en');
      },
      home: WorkbenchPage(
        controller: controller,
        chatController: chatController,
        configController: configController,
        llmConfigController: llmConfigController,
        layoutController: layoutController ?? LayoutController(),
      ),
    );
  }
}

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({
    required this.controller,
    required this.chatController,
    required this.configController,
    required this.llmConfigController,
    required this.layoutController,
    super.key,
  });

  final TeamController controller;
  final ChatController chatController;
  final ConfigController configController;
  final LlmConfigController llmConfigController;
  final LayoutController layoutController;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  AppSection _section = AppSection.chat;

  TeamController get controller => widget.controller;
  ChatController get chatController => widget.chatController;
  ConfigController get configController => widget.configController;
  LlmConfigController get llmConfigController => widget.llmConfigController;
  LayoutController get layoutController => widget.layoutController;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleControllerChanged);
    chatController.addListener(_handleControllerChanged);
    configController.addListener(_handleControllerChanged);
    llmConfigController.addListener(_handleControllerChanged);
    layoutController.addListener(_handleControllerChanged);
    final selected = controller.selectedTeam;
    if (selected != null) {
      chatController.syncTeam(selected);
      configController.syncTeam(selected);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    chatController.removeListener(_handleControllerChanged);
    configController.removeListener(_handleControllerChanged);
    llmConfigController.removeListener(_handleControllerChanged);
    layoutController.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final selected = controller.selectedTeam;
    if (selected != null) {
      chatController.syncTeam(selected);
      configController.syncTeam(selected);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedTeam;
    final preferences = layoutController.preferences;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (preferences.appRailVisible)
              AppRail(
                selected: _section,
                onSelected: (section) => setState(() => _section = section),
              ),
            if (preferences.contextSidebarVisible)
              ContextSidebar(
                controller: controller,
                selectedSectionLabel: _section == AppSection.config
                    ? 'Config'
                    : 'Chat',
                configController: configController,
                llmConfigController: llmConfigController,
              ),
            if (selected == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_section == AppSection.config)
              WorkspaceShell(
                breadcrumb: configController.breadcrumb,
                title: configController.title,
                subtitle: _configSubtitle(selected),
                actions: const [],
                child: ConfigWorkspace(
                  configController: configController,
                  layoutController: layoutController,
                  llmConfigController: llmConfigController,
                  teamController: controller,
                ),
              )
            else
              WorkspaceShell(
                breadcrumb: '${selected.name} / Chat / Shell chat workbench',
                title: 'Shell chat workbench',
                subtitle:
                    'target: ${chatController.selectedMemberName(selected)} / shell wrapper mode',
                layoutPreferences: preferences,
                onRightToolsWidthChanged: layoutController.setRightToolsWidth,
                actions: [
                  IconButton.filledTonal(
                    key: AppKeys.openTeamLeadButton,
                    tooltip: 'Open team-lead',
                    onPressed: controller.isLaunching
                        ? null
                        : () => _openTeamLead(selected),
                    icon: const Icon(Icons.person_outline),
                  ),
                  IconButton.filled(
                    key: AppKeys.openTeamButton,
                    tooltip: 'Open Team',
                    onPressed: controller.isLaunching ? null : _openTeam,
                    icon: const Icon(Icons.groups_outlined),
                  ),
                ],
                rightTools: RightToolsPanel(
                  team: selected,
                  chatController: chatController,
                  onOpenMember: _openMember,
                  preferences: preferences,
                  panelKey:
                      preferences.toolPlacement == ToolPanelPlacement.right
                      ? AppKeys.rightToolsPanel
                      : AppKeys.bottomToolsPanel,
                ),
                child: ChatWorkbench(
                  team: selected,
                  chatController: chatController,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTeamLead(TeamConfig team) async {
    final lead = team.members.where((member) => member.name == 'team-lead');
    if (lead.isEmpty) {
      chatController.addSystemMessage(
        'FlashskyAI requires a member named team-lead before opening the team lead.',
      );
      return;
    }
    await controller.launchMember(lead.first.id);
    chatController.addSystemMessage(controller.statusMessage);
  }

  Future<void> _openMember(String memberId) async {
    final team = controller.selectedTeam;
    if (team == null) {
      return;
    }
    await controller.launchMember(memberId);
    chatController.addSystemMessage(controller.statusMessage);
  }

  Future<void> _openTeam() async {
    final team = controller.selectedTeam;
    if (team == null) {
      return;
    }
    await controller.launchSelectedTeam();
    chatController.addSystemMessage(controller.statusMessage);
  }

  String _configSubtitle(TeamConfig team) {
    final member = team.members
        .where((item) => item.id == configController.selectedMemberId)
        .firstOrNull;
    return switch (configController.section) {
      ConfigSection.team => '${team.name} / ${team.members.length} members',
      ConfigSection.members =>
        '${team.name} / ${member?.name ?? 'select a member'}',
      ConfigSection.layout => 'Global workbench layout preferences',
      ConfigSection.llm =>
        '${llmConfigController.filePath} / ${llmConfigController.config.providers.length} providers / ${llmConfigController.config.models.length} models',
    };
  }
}
