import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/chat_workbench_terminal.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/post_frame_test_harness.dart';

class _SpyTerminalSession extends TerminalSession {
  _SpyTerminalSession({required super.executable});

  var connectCalls = 0;
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  bool get isConnected => _running;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    shellLaunch,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    busUserInputRouting,
    String? executableOverride,
  }) {
    connectCalls++;
    _running = true;
    onProcessStarted?.call();
  }

  @override
  void dispose() {
    _running = false;
  }
}

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit({
    required super.executableResolver,
    required super.automationRepository,
    required super.sessionRepository,
    required super.postFrameScheduler,
    required super.terminalSessionFactory,
    this.forwardOpen = false,
  });

  final bool forwardOpen;
  final openRequests = <SessionOpenRequest>[];

  @override
  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) {
    openRequests.add(request);
    if (!forwardOpen) {
      return Future.value(SessionOpenStatus.opened);
    }
    return super.requestOpenSession(request);
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('sidebar open-existing builder sets connectImmediately: false', () {
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/tmp')],
      createdAt: 1,
      updatedAt: 1,
    );
    final request = buildOpenExistingSessionRequest(
      session: session,
      workspace: Workspace(workspaceId: 'ws-1', createdAt: 1),
      emptyDisplayTitleFallback: 'New Chat',
    );
    expect(request.connectImmediately, isFalse);
  });

  test(
    'sidebar open-existing builder can request connectImmediately: true',
    () {
      final session = AppSession(
        sessionId: 'sess-1',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/tmp')],
        createdAt: 1,
        updatedAt: 1,
      );
      final request = buildOpenExistingSessionRequest(
        session: session,
        workspace: Workspace(workspaceId: 'ws-1', createdAt: 1),
        emptyDisplayTitleFallback: 'New Chat',
        connectImmediately: true,
      );
      expect(request.connectImmediately, isTrue);
    },
  );

  group('open-existing gate with ChatCubit', () {
    late Directory tmp;
    late SessionRepository repo;
    late PostFrameTestHarness postFrame;
    late _RecordingChatCubit chatCubit;
    late LaunchProfileCubit launchProfiles;
    final shells = <_SpyTerminalSession>[];

    Future<void> boot({required bool forwardOpen}) async {
      tmp = await Directory.systemTemp.createTemp('open_existing_gate_');
      repo = SessionRepository(rootDir: tmp.path);
      postFrame = PostFrameTestHarness();
      shells.clear();
      chatCubit = _RecordingChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        postFrameScheduler: postFrame.scheduler,
        forwardOpen: forwardOpen,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final shell = _SpyTerminalSession(executable: executable);
              shells.add(shell);
              return shell;
            },
      );
      launchProfiles = LaunchProfileCubit(
        repository: testLaunchProfileRepository(tmp),
        sessionRepository: repo,
        executableResolver: () => 'true',
      );
    }

    Future<void> shutdown() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await chatCubit.close();
      await launchProfiles.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    }

    test(
      'route deep-link open-existing passes connectImmediately: false',
      () async {
        await boot(forwardOpen: false);
        addTearDown(shutdown);

        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
        await chatCubit.loadWorkspaceData(repo);

        final l10n = lookupAppLocalizations(const Locale('en'));
        var handled = false;
        consumeChatWorkbenchRouteSession(
          routeSessionId: session.sessionId,
          handledRouteSession: false,
          state: chatCubit.state,
          chatCubit: chatCubit,
          teamCubit: launchProfiles,
          sessionRepo: repo,
          l10n: l10n,
          onHandled: (v) => handled = v,
        );
        await drainPendingAsyncWork();

        expect(handled, isTrue);
        expect(chatCubit.openRequests, hasLength(1));
        expect(chatCubit.openRequests.single.connectImmediately, isFalse);
      },
    );

    test('route deep-link respects connectImmediately: true', () async {
      await boot(forwardOpen: false);
      addTearDown(shutdown);

      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);
      await chatCubit.loadWorkspaceData(repo);

      final l10n = lookupAppLocalizations(const Locale('en'));
      consumeChatWorkbenchRouteSession(
        routeSessionId: session.sessionId,
        handledRouteSession: false,
        state: chatCubit.state,
        chatCubit: chatCubit,
        teamCubit: launchProfiles,
        sessionRepo: repo,
        l10n: l10n,
        onHandled: (_) {},
        connectImmediately: true,
      );
      await drainPendingAsyncWork();

      expect(chatCubit.openRequests, hasLength(1));
      expect(chatCubit.openRequests.single.connectImmediately, isTrue);
    });

    test(
      'open-existing with connectImmediately: false does not begin session connect',
      () async {
        await boot(forwardOpen: true);
        addTearDown(shutdown);

        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        final session = await repo.createSession(workspace.workspaceId);
        await chatCubit.loadWorkspaceData(repo);

        await chatCubit.requestOpenSession(
          buildOpenExistingSessionRequest(
            session: session,
            workspace: workspace,
            repo: repo,
            emptyDisplayTitleFallback: 'New Chat',
          ),
        );
        await drainPendingAsyncWork();
        await postFrame.flush();
        await drainPendingAsyncWork();

        expect(chatCubit.hasConnectingSession, isFalse);
        expect(chatCubit.isSessionConnecting(session.sessionId), isFalse);
        expect(shells.fold<int>(0, (sum, s) => sum + s.connectCalls), 0);
      },
    );

    test(
      'landing-style create+open still connects immediately by default',
      () async {
        await boot(forwardOpen: true);
        addTearDown(shutdown);

        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: '/tmp'),
        ]);
        await chatCubit.loadWorkspaceData(repo);

        final status = await chatCubit.requestCreateAndOpenSession(
          SessionCreateRequest(
            workspace: workspace,
            isPersonal: true,
            repo: repo,
          ),
        );
        await waitUntil(() => postFrame.hasPendingCallbacks);
        await postFrame.flush();
        await waitUntil(
          () => shells.fold<int>(0, (sum, s) => sum + s.connectCalls) > 0,
        );
        await postFrame.flush();

        expect(status, SessionOpenStatus.opened);
        expect(
          shells.fold<int>(0, (sum, s) => sum + s.connectCalls),
          greaterThan(0),
        );
      },
    );
  });
}
