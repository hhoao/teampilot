import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:multi_split_view/multi_split_view.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../pages/chat_page.dart';
import '../pages/config_workspace.dart';
import '../widgets/context_sidebar.dart';

final appRouter = GoRouter(
  initialLocation: '/chat',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final sw = Stopwatch()..start();
        final layoutCubit = context.watch<LayoutCubit>();
        final preferences = layoutCubit.state.preferences;
        final areas = <Area>[
          if (preferences.contextSidebarVisible)
            Area(
                min: 180,
                size: preferences.sidebarWidth,
                builder: (_, __) => const ContextSidebar()),
          Area(min: 400, builder: (_, __) => child),
        ];
        print('[perf] ShellRoute builder ${state.uri}: ${sw.elapsedMilliseconds}ms');
        return Scaffold(
          body: SafeArea(
            child: MultiSplitViewTheme(
              data: MultiSplitViewThemeData(
                dividerThickness: 4,
                dividerPainter: DividerPainters.grooved1(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  color: Theme.of(context).dividerColor,
                ),
              ),
              child: MultiSplitView(
                key: ValueKey(state.uri.toString()),
                axis: Axis.horizontal,
                initialAreas: areas,
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
                child: ChatPage(
                    sessionId: state.pathParameters['sessionId']),
              ),
            ),
          ],
        ),
        GoRoute(
            path: '/config',
            redirect: (context, state) => '/config/team'),
        GoRoute(
          path: '/config/team',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.team),
          ),
        ),
        GoRoute(
          path: '/config/members',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.members),
          ),
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
      ],
    ),
  ],
);
