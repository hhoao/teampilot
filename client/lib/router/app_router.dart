import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../pages/chat_page.dart';
import '../pages/config_workspace.dart';
import '../pages/team_config_page.dart';
import '../utils/logger.dart';
import '../utils/perf.dart';
import '../widgets/context_sidebar.dart';
import '../widgets/resizable_split_view.dart';

final appRouter = GoRouter(
  initialLocation: '/chat',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final sw = Stopwatch()..start();
        final layoutCubit = context.watch<LayoutCubit>();
        final preferences = layoutCubit.state.preferences;
        appLogger.d(
          '[perf] ShellRoute builder ${state.uri}: ${sw.elapsedMilliseconds}ms',
        );
        return Scaffold(
          body: SafeArea(
            child: PipelinePerf(
              label: 'shell split ${state.uri}',
              child: preferences.contextSidebarVisible
                  ? ResizableSplitView(
                      initialLeftWidth: preferences.sidebarWidth,
                      minLeftWidth: 180,
                      maxLeftWidth: 420,
                      dividerWidth: 6,
                      onWidthChanged: (width) {
                        context.read<LayoutCubit>().setSidebarWidth(width);
                      },
                      left: const RepaintBoundary(child: ContextSidebar()),
                      right: child,
                    )
                  : child,
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
        GoRoute(path: '/config', redirect: (context, state) => '/config/layout'),
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
          path: '/team-config',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(),
          ),
        ),
      ],
    ),
  ],
);
