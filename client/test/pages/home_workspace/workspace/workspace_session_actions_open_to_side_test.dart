import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';

import '../../../support/post_frame_test_harness.dart';

void main() {
  testWidgets(
    'openWorkspaceSessionTabToSide splits the session into a new right group',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sessionPreferencesCubit = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(prefs),
      );
      addTearDown(sessionPreferencesCubit.close);

      Future<
        (
          ChatCubit,
          WorkbenchCubit,
          Workspace,
          AppSession,
          AppSession,
          SessionRepository,
        )
      >
      setup() async {
        final tmp = await Directory.systemTemp.createTemp('open_to_side_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: tmp.path),
        ]);
        final sessionA = (await repo.createSession(workspace.workspaceId)).session;
        final sessionB = (await repo.createSession(workspace.workspaceId)).session;
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
        );
        final workbench = WorkbenchCubit();
        final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
        workbench.port = bridge;
        cubit.workbenchPort = bridge;
        cubit.onSessionTabOpened = bridge.onSessionTabOpened;
        await cubit.loadWorkspaceData(repo);
        // Session A opens first so the focused group already hosts a tab.
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: sessionA,
            workspace: workspace,
            repo: repo,
          ),
        );
        return (cubit, workbench, workspace, sessionA, sessionB, repo);
      }

      final result = await tester.runAsync(setup);
      expect(result, isNotNull);
      final (chatCubit, workbench, workspace, sessionA, sessionB, repo) =
          result!;
      addTearDown(workbench.close);
      addTearDown(chatCubit.close);

      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => MultiRepositoryProvider(
                  providers: [
                    RepositoryProvider<SessionRepository>.value(value: repo),
                  ],
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<ChatCubit>.value(value: chatCubit),
                      BlocProvider<WorkbenchCubit>.value(value: workbench),
                      BlocProvider<SessionPreferencesCubit>.value(
                        value: sessionPreferencesCubit,
                      ),
                    ],
                    child: Scaffold(
                      body: Builder(
                        builder: (context) => Center(
                          child: TextButton(
                            onPressed: () => openWorkspaceSessionTabToSide(
                              context,
                              sessionB,
                            ),
                            child: const Text('open-to-side'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('open-to-side'));
      await tester.pumpAndSettle();

      final layout = workbench.centerLayout(workspace.workspaceId);
      expect(layout.leafGroupIds, hasLength(2));
      expect(
        layout.groups[layout.leafGroupIds.first]!.order,
        [WorkbenchTabId.session(sessionA.sessionId)],
      );
      expect(
        layout.groups[layout.leafGroupIds.last]!.order,
        [WorkbenchTabId.session(sessionB.sessionId)],
      );
      expect(layout.focusedGroupId, layout.leafGroupIds.last);
      expect(validateLayout(layout), isTrue);
    },
  );
}
