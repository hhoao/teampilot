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
import '../pages/skill_management_page.dart';
import '../pages/team_config_page.dart';
import '../repositories/session_repository.dart';
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
        return Scaffold(
          body: SafeArea(
            child: preferences.contextSidebarVisible
                ? ResizableSplitView(
                    initialLeftWidth: preferences.sidebarWidth,
                    minLeftWidth: 180,
                    maxLeftWidth: 420,
                    onWidthChanged: (width) {
                      context.read<LayoutCubit>().setSidebarWidth(width);
                    },
                    left: RepaintBoundary(
                      child: ContextSidebar(
                        onNewProject: () => _createProject(context),
                      ),
                    ),
                    right: child,
                  )
                : child,
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
          redirect: (context, state) => '/config/layout',
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
          path: '/config/session',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.session),
          ),
        ),
        GoRoute(
          path: '/team-config',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: TeamConfigPage()),
        ),
        GoRoute(
          path: '/skills',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SkillManagementPage()),
        ),
      ],
    ),
  ],
);

Future<void> _createProject(BuildContext context) async {
  final dir = await FilePicker.platform.getDirectoryPath();
  if (dir != null && context.mounted) {
    final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
    await context.read<ChatCubit>().createProjectWithFirstSession(
      dir,
      SessionRepository(),
      sessionTeamId: teamId,
    );
  }
}
