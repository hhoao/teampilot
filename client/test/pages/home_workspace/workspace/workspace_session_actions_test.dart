import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/repositories/session_repository_fs.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit({this.failRename = false})
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final bool failRename;
  final prompts = <(String, String)>[];

  @override
  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt,
  ) async {
    prompts.add((sessionId, firstPrompt));
    if (failRename) throw StateError('rename failed');
  }
}

class _FailingSessionRepository extends SessionRepository {
  @override
  Future<SessionRepositoryFs> fs() async {
    throw StateError('storage unavailable');
  }
}

class _RecordingNotificationRecorder implements NotificationRecorder {
  final records = <({String message, TpToastVariant variant})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((message: message, variant: variant));
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(() {
    NotificationRecorder.install(null);
    TpToast.dismiss();
    tearDownTestAppStorage();
  });

  test(
    'applyLandingPromptTitleBestEffort forwards the landing prompt',
    () async {
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);

      await applyLandingPromptTitleBestEffort(
        chatCubit: chat,
        sessionId: 'sess-1',
        prompt: 'fix the title',
      );

      expect(chat.prompts, [('sess-1', 'fix the title')]);
    },
  );

  test('applyLandingPromptTitleBestEffort swallows rename errors', () async {
    final chat = _RecordingChatCubit(failRename: true);
    addTearDown(chat.close);

    await expectLater(
      applyLandingPromptTitleBestEffort(
        chatCubit: chat,
        sessionId: 'sess-1',
        prompt: 'fix the title',
      ),
      completes,
    );

    expect(chat.prompts, [('sess-1', 'fix the title')]);
  });

  testWidgets('referenceWorkspaceSession opens Landing with the session path', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    final workbench = WorkbenchCubit();
    final bridge = WorkbenchChatBridge(workbench: workbench, chat: chat);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: workspace.workspaceId,
      createdAt: 1,
    );
    final contextKey = GlobalKey();
    addTearDown(chat.close);
    addTearDown(workbench.close);
    workbench.port = bridge;
    chat.workbenchPort = bridge;
    workbench.openSession(workspace.workspaceId, 'existing');
    chat.applyState(chat.state.copyWith(workspaces: [workspace]));

    await tester.pumpWidget(
      MaterialApp(
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<SessionRepository>.value(
              value: SessionRepository(rootDir: '/teampilot'),
            ),
          ],
          child: BlocProvider<ChatCubit>.value(
            value: chat,
            child: Builder(builder: (context) => SizedBox(key: contextKey)),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => referenceWorkspaceSession(
        tester.element(find.byKey(contextKey)),
        session,
      ),
    );

    final bar = workbench.state.bar(workspace.workspaceId);
    expect(bar.center.activeId, isNull);
    expect(bar.center.order, [WorkbenchTabId.session('existing')]);
    expect(
      bar.center.landingInitialText,
      '审查并继续完成该会话: '
      '/teampilot/workspace/workspaces/ws1/sessions/sess-1',
    );
    expect(bar.center.landingReferenceSessionId, session.sessionId);
  });

  testWidgets('referenceWorkspaceSession reports storage failures', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    final workbench = WorkbenchCubit();
    final bridge = WorkbenchChatBridge(workbench: workbench, chat: chat);
    final recorder = _RecordingNotificationRecorder();
    final contextKey = GlobalKey();
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      createdAt: 1,
    );
    addTearDown(chat.close);
    addTearDown(workbench.close);
    NotificationRecorder.install(recorder);
    workbench.port = bridge;
    chat.workbenchPort = bridge;
    workbench.openSession('ws1', 'existing');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<SessionRepository>.value(
              value: _FailingSessionRepository(),
            ),
          ],
          child: BlocProvider<ChatCubit>.value(
            value: chat,
            child: Builder(builder: (context) => SizedBox(key: contextKey)),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => referenceWorkspaceSession(
        tester.element(find.byKey(contextKey)),
        session,
      ),
    );

    expect(workbench.centerActiveId('ws1'), WorkbenchTabId.session('existing'));
    expect(recorder.records, hasLength(1));
    expect(
      recorder.records.single.message,
      'Failed to prepare conversation reference',
    );
    expect(recorder.records.single.variant, TpToastVariant.error);
  });

  testWidgets(
    'deleting a referenced session clears Landing when its tab was never opened',
    (tester) async {
      late Directory tmp;
      late SessionRepository repo;
      late Workspace workspace;
      late AppSession session;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp(
          'reference_session_delete_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        repo = SessionRepository(rootDir: tmp.path);
        workspace = await repo.createWorkspace([WorkspaceFolder(path: '/a')]);
        session = (await repo.createSession(
          workspace.workspaceId,
          sessionTeam: '',
          rosterMembers: const [],
        )).session;
      });
      final chat = _RecordingChatCubit();
      final workbench = WorkbenchCubit();
      final bridge = WorkbenchChatBridge(workbench: workbench, chat: chat);
      final contextKey = GlobalKey();
      addTearDown(chat.close);
      addTearDown(workbench.close);
      workbench.port = bridge;
      chat.workbenchPort = bridge;
      chat.applyState(
        chat.state.copyWith(workspaces: [workspace], sessions: [session]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(value: repo),
            ],
            child: BlocProvider<ChatCubit>.value(
              value: chat,
              child: Builder(builder: (context) => SizedBox(key: contextKey)),
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => referenceWorkspaceSession(
          tester.element(find.byKey(contextKey)),
          session,
        ),
      );
      expect(
        workbench.state.bar(workspace.workspaceId).center.landingInitialText,
        isNotNull,
      );

      await tester.runAsync(() => chat.deleteSession(repo, session.sessionId));

      expect(
        workbench.state.bar(workspace.workspaceId).center.landingInitialText,
        isNull,
      );
      expect(
        workbench.state
            .bar(workspace.workspaceId)
            .center
            .landingReferenceSessionId,
        isNull,
      );
    },
  );
}
