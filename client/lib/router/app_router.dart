import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/team_cubit.dart';
import '../pages/chat_page.dart';
import '../pages/config_workspace.dart';
import '../pages/llm_config_workspace.dart';
import '../pages/skill_management_page.dart';
import '../pages/startup_gate.dart';
import '../pages/ssh_profiles_page.dart';
import '../pages/team_config_page.dart';
import '../widgets/android_ssh_profile_selector.dart';
import '../repositories/session_repository.dart';
import '../services/platform_utils.dart';
import 'android_shell_chrome.dart';
import '../widgets/context_sidebar.dart';
import '../widgets/resizable_split_view.dart';

final appRouter = GoRouter(
  initialLocation: '/chat',
  routes: [
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
            ? ResizableSplitView(
                initialLeftWidth: preferences.sidebarWidth,
                minLeftWidth: 180,
                maxLeftWidth: 420,
                onWidthChanged: (width) {
                  context.read<LayoutCubit>().setSidebarWidth(width);
                },
                left: sidebar,
                right: child,
              )
            : child;

        if (Platform.isAndroid) {
          final path = state.uri.path;
          final hubDetail = AndroidShellChrome.isHubDetailPath(path);
          return StartupGate(
            child: Scaffold(
              appBar: AppBar(
                title: Text(AndroidShellChrome.title(context, path)),
                leading: hubDetail
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => AndroidShellChrome.pop(context, path),
                      )
                    : null,
                actions: const [AndroidSshProfileSelector()],
              ),
              drawer: hubDetail
                  ? null
                  : Drawer(child: SafeArea(child: sidebar)),
              body: body,
            ),
          );
        }

        return Scaffold(
          body: SafeArea(child: StartupGate(child: body)),
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
          path: '/config/llm/provider/:providerName',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LlmProviderConfigPage(
              providerName: Uri.decodeComponent(
                state.pathParameters['providerName']!,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/config/llm/provider/:providerName/models',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LlmProviderModelsPage(
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
          path: '/skills/backups',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SkillManagementPage(section: SkillSection.backups),
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

Future<void> _createProject(BuildContext context) async {
  closeAndroidDrawerIfOpen(context);
  String? path;
  if (Platform.isAndroid) {
    if (!context.mounted) return;
    path = await _promptRemoteProjectPath(context);
  } else {
    path = await FilePicker.platform.getDirectoryPath();
  }
  if (path != null && path.trim().isNotEmpty && context.mounted) {
    final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
    await context.read<ChatCubit>().createProjectWithFirstSession(
      path.trim(),
      context.read<SessionRepository>(),
      sessionTeamId: teamId,
    );
  }
}

Future<String?> _promptRemoteProjectPath(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => const _RemoteProjectPathDialog(),
  );
}

class _RemoteProjectPathDialog extends StatefulWidget {
  const _RemoteProjectPathDialog();

  @override
  State<_RemoteProjectPathDialog> createState() =>
      _RemoteProjectPathDialogState();
}

class _RemoteProjectPathDialogState extends State<_RemoteProjectPathDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '~/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remote Project Path'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Path on SSH host',
            hintText: '~/work/project',
          ),
          textInputAction: TextInputAction.done,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Required';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
