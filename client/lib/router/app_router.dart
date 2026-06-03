import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/app_provider_config.dart';
import '../models/layout_preferences.dart';
import '../pages/chat_page.dart';
import '../pages/config_workspace.dart';
import '../pages/home_workspace/home_workspace_page.dart';
import '../pages/home_workspace/home_workspace_shell.dart';
import '../pages/home_workspace/project/home_workspace_project_page.dart';
import '../pages/llm_config/llm_config_workspace.dart';
import '../pages/extensions/extension_management_page.dart';
import '../pages/skills/skill_management_page.dart';
import '../pages/plugins/plugin_management_page.dart';
import '../pages/mcp/mcp_form_nav_page.dart';
import '../pages/mcp/mcp_management_page.dart';
import '../pages/onboarding/onboarding_gate.dart';
import '../pages/startup_gate.dart';
import '../pages/ssh_profiles_page.dart';
import '../pages/team_config/team_config_page.dart';
import '../widgets/android_ssh_profile_selector.dart';
import '../repositories/session_repository.dart';
import '../services/app/platform_utils.dart';
import 'android_shell_chrome.dart';
import '../widgets/context_sidebar.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/create_project_dialog.dart';
import '../widgets/split_layout.dart';
import '../l10n/l10n_extensions.dart';

final appRouter = GoRouter(
  // Dev entry for the new workspace home. Revert to '/chat' to restore the
  // legacy shell as the default landing route.
  initialLocation: '/home-v2',
  routes: [
    // New Apifox-style workspace home — standalone, outside the legacy shell.
    // The shell draws the persistent title bar + open project tabs; the home
    // and project routes render only the body below it.
    ShellRoute(
      builder: (context, state, child) =>
          HomeWorkspaceShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/home-v2',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeWorkspacePage()),
        ),
        GoRoute(
          path: '/home-v2/project/:projectId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: HomeWorkspaceProjectPage(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
        ),
      ],
    ),
    ShellRoute(
      builder: (context, state, child) {
        final layoutCubit = context.watch<LayoutCubit>();
        final preferences = layoutCubit.state.preferences;
        final scopeOn = context
            .watch<SessionPreferencesCubit>()
            .state
            .preferences
            .scopeSessionsToSelectedTeam;
        final selectedTeam = context.watch<TeamCubit>().state.selectedTeam;
        context.read<ChatCubit>().setTeamSessionScope(
          scopeSessionsToSelectedTeam: scopeOn,
          selectedTeamId: selectedTeam?.id,
        );

        final sidebar = RepaintBoundary(
          child: ContextSidebar(onNewProject: () => _createProject(context)),
        );

        final body = Platform.isAndroid
            ? child
            : preferences.contextSidebarVisible
            ? TwoPaneSplitView(
                axis: Axis.horizontal,
                first: sidebar,
                second: child,
                initialSize: preferences.sidebarWidth,
                minSize: LayoutPreferences.minSidebarWidth,
                minSecondarySize: LayoutPreferences.minWorkbenchMainWidth,
                maxSize: LayoutPreferences.maxSidebarWidth,
                onSizeChanged: (width) {
                  context.read<LayoutCubit>().setSidebarWidth(width);
                },
              )
            : child;

        if (Platform.isAndroid) {
          final path = state.uri.path;
          final hubDetail = AndroidShellChrome.isHubDetailPath(path);
          return OnboardingGate(
            child: StartupGate(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(AndroidShellChrome.title(context, path)),
                  leading: hubDetail
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () =>
                              AndroidShellChrome.pop(context, path),
                        )
                      : null,
                  actions: const [AndroidSshProfileSelector()],
                ),
                drawer: hubDetail
                    ? null
                    : Drawer(child: SafeArea(child: sidebar)),
                body: body,
              ),
            ),
          );
        }

        return OnboardingGate(
          child: StartupGate(
            child: Scaffold(
              body: DesktopWindowChrome(
                child: SafeArea(top: false, child: body),
              ),
            ),
          ),
        );
      },
      routes: [
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ChatPage()),
          routes: [
            GoRoute(
              path: 'session/:sessionId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ChatPage(sessionId: state.pathParameters['sessionId']),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/config',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/config/layout';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ConfigSettingsHubPage()),
        ),
        GoRoute(
          path: '/config/layout',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.layout),
          ),
        ),
        GoRoute(
          path: '/config/llm',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.llm),
          ),
        ),
        GoRoute(
          path: '/config/llm/:cli',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ConfigWorkspace(
              section: ConfigSection.llm,
              initialProviderCli: _appProviderCliFromRoute(state),
            ),
          ),
        ),
        GoRoute(
          path: '/config/llm/:cli/provider/add',
          pageBuilder: (context, state) => NoTransitionPage(
            child: Platform.isAndroid
                ? LlmProviderAddPage(cli: _appProviderCliFromRoute(state))
                : ConfigWorkspace(
                    section: ConfigSection.llm,
                    initialProviderCli: _appProviderCliFromRoute(state),
                    showAddProviderOnOpen: true,
                  ),
          ),
        ),
        GoRoute(
          path: '/config/llm/:cli/provider/:providerName',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LlmProviderConfigPage(
              cli: _appProviderCliFromRoute(state),
              providerName: Uri.decodeComponent(
                state.pathParameters['providerName']!,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/config/llm/:cli/provider/:providerName/edit',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LlmProviderEditPage(
              cli: _appProviderCliFromRoute(state),
              providerName: Uri.decodeComponent(
                state.pathParameters['providerName']!,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/config/llm/:cli/provider/:providerName/models',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LlmProviderModelsPage(
              cli: _appProviderCliFromRoute(state),
              providerName: Uri.decodeComponent(
                state.pathParameters['providerName']!,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/config/session',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.session),
          ),
        ),
        GoRoute(
          path: '/config/ssh-profiles',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SshProfilesPage(embedded: true)),
        ),
        GoRoute(
          path: '/config/about',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.about),
          ),
        ),
        GoRoute(
          path: '/config/logs',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.logs),
          ),
        ),
        GoRoute(
          path: '/team-config',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/team-config/team';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: TeamConfigHubPage()),
        ),
        GoRoute(
          path: '/team-config/team',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.team),
          ),
        ),
        GoRoute(
          path: '/team-config/skills',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.skills),
          ),
        ),
        GoRoute(
          path: '/team-config/plugins',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.plugins),
          ),
        ),
        GoRoute(
          path: '/team-config/mcp',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.mcp),
          ),
        ),
        GoRoute(
          path: '/team-config/extensions',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(section: TeamConfigSection.extensions),
          ),
        ),
        GoRoute(
          path: '/team-config/members/:memberId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: TeamConfigPage(
              section: TeamConfigSection.members,
              memberId: state.pathParameters['memberId'],
            ),
          ),
        ),
        GoRoute(
          path: '/skills',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/skills/installed';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SkillManagementHubPage()),
        ),
        GoRoute(
          path: '/skills/installed',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillManagementPage(section: SkillSection.installed),
          ),
        ),
        GoRoute(
          path: '/skills/discovery',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillManagementPage(section: SkillSection.discovery),
          ),
        ),
        GoRoute(
          path: '/skills/repos',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillManagementPage(section: SkillSection.repos),
          ),
        ),
        GoRoute(
          path: '/extensions',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/extensions/installed';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ExtensionManagementHubPage()),
        ),
        GoRoute(
          path: '/extensions/installed',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ExtensionManagementPage(section: ExtensionSection.installed),
          ),
        ),
        GoRoute(
          path: '/plugins',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/plugins/installed';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: PluginManagementHubPage()),
        ),
        GoRoute(
          path: '/plugins/installed',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PluginManagementPage(section: PluginSection.installed),
          ),
        ),
        GoRoute(
          path: '/plugins/discovery',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PluginManagementPage(section: PluginSection.discovery),
          ),
        ),
        GoRoute(
          path: '/plugins/marketplaces',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PluginManagementPage(section: PluginSection.marketplaces),
          ),
        ),
        GoRoute(
          path: '/mcp',
          redirect: (context, state) {
            if (Platform.isAndroid) return null;
            return '/mcp/installed';
          },
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: McpManagementHubPage()),
        ),
        GoRoute(
          path: '/mcp/installed',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: McpManagementPage(section: McpSection.installed),
          ),
        ),
        GoRoute(
          path: '/mcp/discovery',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: McpManagementPage(section: McpSection.discovery),
          ),
        ),
        GoRoute(
          path: '/mcp/registries',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: McpManagementPage(section: McpSection.registries),
          ),
        ),
        GoRoute(
          path: '/mcp/add',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: McpFormNavPage()),
        ),
        GoRoute(
          path: '/mcp/edit/:serverId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: McpFormNavPage(
              serverId: Uri.decodeComponent(state.pathParameters['serverId']!),
            ),
          ),
        ),
        GoRoute(
          path: '/ssh-profiles',
          redirect: (context, state) => '/config/ssh-profiles',
        ),
      ],
    ),
  ],
);

AppProviderCli _appProviderCliFromRoute(GoRouterState state) {
  return AppProviderCli.parse(state.pathParameters['cli']);
}

Future<void> _createProject(BuildContext context) async {
  closeAndroidDrawerIfOpen(context);
  final draft = await showCreateProjectDialog(context);
  if (draft == null || !context.mounted) return;
  final team = context.read<TeamCubit>().state.selectedTeam;
  final teamId = team?.id ?? '';
  try {
    await context.read<ChatCubit>().createProjectWithFirstSession(
      draft.primaryPath,
      context.read<SessionRepository>(),
      sessionTeamId: teamId,
      rosterMembers: team?.members ?? const [],
      additionalPaths: draft.additionalPaths,
      display: draft.display,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.l10n.newProject}: $error')),
    );
  }
}
