import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../models/app_provider_config.dart';
import '../models/launch_identity.dart';
import '../pages/config/config_workspace.dart';
import '../pages/home_workspace/home_workspace_global_section.dart';
import '../pages/home_workspace/home_workspace_page.dart';
import '../pages/home_workspace/home_workspace_shell.dart';
import '../pages/home_workspace/workspace/home_workspace_workspace_page.dart';
import '../pages/home_workspace/workspace/workspace_config_section.dart';
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
import 'android_shell_chrome.dart';
import '../models/layout_preferences.dart';
import '../widgets/desktop_window_title_bar.dart';

final _workspaceEntryNotifier = ValueNotifier<String>('/home-v2');

@visibleForTesting
String workspaceEntryLocationFor({
  required WorkspaceEntryMode mode,
  String? lastOpenedWorkspaceId,
}) {
  if (mode != WorkspaceEntryMode.lastWorkspace) {
    return '/home-v2';
  }
  final workspaceId = lastOpenedWorkspaceId?.trim() ?? '';
  if (workspaceId.isEmpty) {
    return '/home-v2';
  }
  return '/home-v2/workspace/$workspaceId';
}

/// Apply the user's startup view preference. Call after [LayoutCubit.load()]
/// during bootstrap, before the first route is resolved.
void applyWorkspaceEntryMode(
  WorkspaceEntryMode mode, {
  String? lastOpenedWorkspaceId,
}) {
  _workspaceEntryNotifier.value = workspaceEntryLocationFor(
    mode: mode,
    lastOpenedWorkspaceId: lastOpenedWorkspaceId,
  );
}

/// Re-apply [lastWorkspace] after workspace index loads so missing ids fall back.
void reapplyWorkspaceEntryFromPreferences(
  LayoutPreferences preferences, {
  Set<String>? knownWorkspaceIds,
}) {
  if (preferences.workspaceEntryMode != WorkspaceEntryMode.lastWorkspace) {
    return;
  }
  final workspaceId = preferences.lastOpenedWorkspaceId.trim();
  if (workspaceId.isEmpty) {
    applyWorkspaceEntryMode(WorkspaceEntryMode.home);
    return;
  }
  if (knownWorkspaceIds != null && !knownWorkspaceIds.contains(workspaceId)) {
    applyWorkspaceEntryMode(WorkspaceEntryMode.home);
    return;
  }
  applyWorkspaceEntryMode(
    WorkspaceEntryMode.lastWorkspace,
    lastOpenedWorkspaceId: workspaceId,
  );
}

final appRouter = GoRouter(
  refreshListenable: _workspaceEntryNotifier,
  initialLocation: _workspaceEntryNotifier.value,
  routes: [
    // App-wide gates run once above both workspace shells so first-run setup
    // and SSH startup checks apply regardless of entry mode.
    ShellRoute(
      builder: (context, state, child) =>
          OnboardingGate(child: StartupGate(child: child)),
      routes: [
        // Apifox-style workspace home — title bar + open workspace tabs live in
        // [HomeShell]; routed pages render only the body below it.
        ShellRoute(
          builder: (context, state, child) => HomeShell(
            location: state.uri.toString(),
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/home-v2',
              pageBuilder: (context, state) {
                final query = state.uri.queryParameters;
                return NoTransitionPage(
                  child: HomePage(
                    initialSection: TeamConfigSection.fromSegment(
                      query['section'],
                    ),
                    initialMemberId: query['member'],
                    initialGlobalView: HomeGlobalView.fromSegment(
                      query[HomeGlobalView.globalQueryParam],
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/home-v2/workspace/:workspaceId/manage',
              redirect: (context, state) {
                final id = state.pathParameters['workspaceId'];
                if (id == null) return '/home-v2';
                final section = state.uri.queryParameters['section'];
                final params = <String, String>{'view': 'manage'};
                if (section != null && section.isNotEmpty) {
                  params['section'] = section;
                }
                return Uri(
                  path: '/home-v2/workspace/$id',
                  queryParameters: params,
                ).toString();
              },
            ),
            GoRoute(
              path: '/home-v2/workspace/:workspaceId',
              pageBuilder: (context, state) {
                final query = state.uri.queryParameters;
                return NoTransitionPage(
                  child: WorkspacePage(
                    workspaceId: state.pathParameters['workspaceId']!,
                    identity: LaunchIdentity.decode(query['as']),
                    view: query['view'],
                    configSection: WorkspaceConfigSection.fromSegment(
                      query['section'],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        ShellRoute(
          builder: _settingsChromeShell,
          routes: [
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
              path: '/config/llm/:cli/provider/:providerName/models',
              redirect: (context, state) =>
                  '/providers/${state.pathParameters['cli']}/provider/${state.pathParameters['providerName']}/models',
            ),
            GoRoute(
              path: '/config/llm/:cli/provider/:providerName/edit',
              redirect: (context, state) =>
                  '/providers/${state.pathParameters['cli']}/provider/${state.pathParameters['providerName']}/edit',
            ),
            GoRoute(
              path: '/config/llm/:cli/provider/:providerName',
              redirect: (context, state) =>
                  '/providers/${state.pathParameters['cli']}/provider/${state.pathParameters['providerName']}',
            ),
            GoRoute(
              path: '/config/llm/:cli/provider/add',
              redirect: (context, state) =>
                  '/providers/${state.pathParameters['cli']}/provider/add',
            ),
            GoRoute(
              path: '/config/llm/:cli',
              redirect: (context, state) =>
                  '/providers/${state.pathParameters['cli']}',
            ),
            GoRoute(
              path: '/config/llm',
              redirect: (context, state) => '/providers/claude',
            ),
            GoRoute(
              path: '/providers',
              redirect: (context, state) {
                if (Platform.isAndroid) return null;
                return '/providers/claude';
              },
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: LlmConfigWorkspace()),
            ),
            GoRoute(
              path: '/providers/:cli',
              pageBuilder: (context, state) => NoTransitionPage(
                child: LlmConfigWorkspace(
                  initialCli: _appProviderCliFromRoute(state),
                ),
              ),
            ),
            GoRoute(
              path: '/providers/:cli/provider/add',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Platform.isAndroid
                    ? LlmProviderAddPage(cli: _appProviderCliFromRoute(state))
                    : LlmConfigWorkspace(
                        initialCli: _appProviderCliFromRoute(state),
                        showAddProviderOnOpen: true,
                      ),
              ),
            ),
            GoRoute(
              path: '/providers/:cli/provider/:providerName',
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
              path: '/providers/:cli/provider/:providerName/edit',
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
              path: '/providers/:cli/provider/:providerName/models',
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
              path: '/config/cli',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.cli),
              ),
            ),
            GoRoute(
              path: '/config/ai-features',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.aiFeatures),
              ),
            ),
            GoRoute(
              path: '/config/ssh-profiles',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SshProfilesPage(embedded: true),
              ),
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
                child: ExtensionManagementPage(
                  section: ExtensionSection.installed,
                ),
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
                child: PluginManagementPage(
                  section: PluginSection.marketplaces,
                ),
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
                  serverId: Uri.decodeComponent(
                    state.pathParameters['serverId']!,
                  ),
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
    ),
  ],
);

Widget _settingsChromeShell(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (Platform.isAndroid) {
    final path = state.uri.path;
    final detail = AndroidShellChrome.isHubDetailPath(path);
    return Scaffold(
      appBar: AppBar(
        title: Text(AndroidShellChrome.title(context, path)),
        leading: detail
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => AndroidShellChrome.pop(context, path),
              )
            : null,
        actions: const [AndroidSshProfileSelector()],
      ),
      body: child,
    );
  }

  return Scaffold(
    body: DesktopWindowChrome(child: SafeArea(top: false, child: child)),
  );
}

CliTool _appProviderCliFromRoute(GoRouterState state) {
  return CliTool.parse(state.pathParameters['cli']);
}
