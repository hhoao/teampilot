import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_executor.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/connect/session_shell_connector.dart';
import 'package:teampilot/services/chat/launch/connect/connect_shell_result.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../../support/fake_terminal_session.dart';
import '../../../support/in_memory_filesystem.dart';
import '../../../support/test_session_persistence_writer.dart';

void main() {
  late List<String> events;
  late _FakeHost host;
  late _FakePreparation preparation;
  late _RecordingConnector shellConnector;
  late SessionConnectExecutor executor;
  late SessionConnectJob job;

  setUp(() {
    events = <String>[];
    host = _FakeHost();
    preparation = _FakePreparation(events, host);
    shellConnector = _RecordingConnector(host, events);
    executor = SessionConnectExecutor(
      preparation: preparation,
      shellConnector: shellConnector,
    );
    job = _job();
  });

  test(
    'executor persists, readies, resolves, installs, then attaches',
    () async {
      await executor.execute(job);

      expect(events, <String>[
        'persist',
        'ensure-ready',
        'resolve-member',
        'install-team-runtime',
        'acquire-shell',
        'connect-shell',
      ]);
    },
  );

  test('executor reports the attachment result after connect', () async {
    final results = <ConnectShellResult>[];
    executor = SessionConnectExecutor(
      preparation: preparation,
      shellConnector: shellConnector,
      onResult: (job, session, resolved, result) {
        results.add(result);
      },
    );

    await executor.execute(job);

    expect(results, [ConnectShellResult.attached]);
  });

  test(
    'executor propagates a failed result for waiting reconnect jobs',
    () async {
      job = _job(propagateErrors: true);
      shellConnector.result = ConnectShellResult.failed;

      await expectLater(
        executor.execute(job),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'session reconnect failed',
          ),
        ),
      );
    },
  );

  test(
    'executor prepares deferred team tabs without attaching a shell',
    () async {
      job = _job(connectShell: false);

      await executor.execute(job);

      expect(events, <String>[
        'persist',
        'ensure-ready',
        'resolve-member',
        'install-team-runtime',
        'mark-deferred-ready',
      ]);
      expect(shellConnector.connectCalls, 0);
    },
  );

  test(
    'executor stops without attachment when the job becomes stale',
    () async {
      preparation.valid = false;

      await executor.execute(job);

      expect(events, isEmpty);
      expect(shellConnector.connectCalls, 0);
    },
  );

  test(
    'executor stops after an awaited preparation stage becomes stale',
    () async {
      final ensureReadyEntered = Completer<void>();
      final releaseEnsureReady = Completer<void>();
      preparation
        ..ensureReadyEntered = ensureReadyEntered
        ..releaseEnsureReady = releaseEnsureReady;

      final execution = executor.execute(job);
      await ensureReadyEntered.future;
      preparation.valid = false;
      releaseEnsureReady.complete();
      await execution;

      expect(events, <String>['persist', 'ensure-ready']);
      expect(shellConnector.connectCalls, 0);
    },
  );

  test('executor rolls back a staged launch when preparation fails', () async {
    preparation.persistError = StateError('persist failed');

    await executor.execute(job);

    expect(preparation.rollbackCalls, 1);
    expect(host.launchErrors, contains(job.sessionId));
  });

  test(
    'executor clears temporary remote resources after connector failure',
    () async {
      shellConnector.connectorError = StateError('attach failed');

      await executor.execute(job);

      expect((job.tab as _RecordingTab).remotePlaneClosed, isTrue);
      expect(host.finishedSessionIds, contains(job.sessionId));
    },
  );

  test('connector failure settles the member materialization waiter', () async {
    shellConnector.result = ConnectShellResult.failed;
    final settled = preparation.materializationSettled;

    await executor.execute(job);
    await settled.future.timeout(const Duration(milliseconds: 200));

    expect(preparation.failedMemberIds, <String>['member-1']);
  });

  test(
    'thrown connector failure settles the member materialization waiter',
    () async {
      shellConnector.connectorError = StateError('attach failed');
      final settled = preparation.materializationSettled;

      await executor.execute(job);
      await settled.future.timeout(const Duration(milliseconds: 200));

      expect(preparation.failedMemberIds, <String>['member-1']);
    },
  );

  test(
    'executor cleans the resolved member when connect fails after staleness',
    () async {
      const resolvedMember = TeamMemberConfig(
        id: 'resolved-member',
        name: 'Resolved Member',
      );
      final connectEntered = Completer<void>();
      final releaseConnect = Completer<void>();
      preparation.resolvedMember = resolvedMember;
      shellConnector
        ..connectorError = StateError('attach failed')
        ..connectEntered = connectEntered
        ..releaseConnect = releaseConnect;

      final execution = executor.execute(job);
      await connectEntered.future;
      preparation.valid = false;
      releaseConnect.complete();
      await execution;

      expect((job.tab as _RecordingTab).closedMemberIds, <String>[
        resolvedMember.id,
      ]);
      expect(host.launchErrors, isEmpty);
    },
  );

  test(
    'cleanup failure preserves the connector error and stack trace',
    () async {
      final connectorError = StateError('attach failed');
      final connectorStackTrace = StackTrace.fromString('connector stack');
      shellConnector
        ..connectorError = connectorError
        ..connectorStackTrace = connectorStackTrace;
      (job.tab as _RecordingTab).closeError = StateError('cleanup failed');

      await executor.execute(job);

      expect(host.launchErrors, <String>[job.sessionId]);
      expect(host.errors.single, same(connectorError));
      expect(host.stackTraces.single, same(connectorStackTrace));
    },
  );
}

SessionConnectJob _job({
  bool connectShell = true,
  bool propagateErrors = false,
}) {
  final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
  const member = TeamMemberConfig(id: 'member-1', name: 'Member');
  const team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: <TeamMemberConfig>[member],
  );
  final session = AppSession(
    sessionId: 'session-1',
    workspaceId: workspace.workspaceId,
    sessionTeam: team.id,
    createdAt: 1,
  );
  final tab = _RecordingTab(
    info: const ChatTabInfo(id: 'session-1', title: 'Session', subtitle: ''),
    cliTeamName: team.id,
  );
  final request = SessionOpenRequest(
    session: session,
    workspace: workspace,
    team: team,
    member: member,
  );
  return SessionConnectJob(
    tab: tab,
    session: session,
    request: request,
    generation: 1,
    workspace: workspace,
    team: team,
    member: member,
    reason: LaunchReason.create,
    connectShell: connectShell,
    propagateErrors: propagateErrors,
  );
}

class _RecordingTab extends ChatTab {
  _RecordingTab({required super.info, required super.cliTeamName});

  final List<String> closedMemberIds = <String>[];
  Object? closeError;

  bool get remotePlaneClosed => closedMemberIds.isNotEmpty;

  @override
  Future<void> closeMemberRemotePlane(String memberId) async {
    closedMemberIds.add(memberId);
    final error = closeError;
    if (error != null) throw error;
  }
}

class _FakePreparation implements SessionConnectPreparationPort {
  _FakePreparation(this.events, this.host);

  final List<String> events;
  final _FakeHost host;
  final TerminalSession shell = FakeTerminalSession(fs: InMemoryFilesystem());
  bool valid = true;
  Object? persistError;
  int rollbackCalls = 0;
  final failedMemberIds = <String>[];
  final materializationSettled = Completer<void>();
  Completer<void>? ensureReadyEntered;
  Completer<void>? releaseEnsureReady;
  TeamMemberConfig? resolvedMember;

  @override
  Future<AppSession> persist(SessionConnectJob job) async {
    events.add('persist');
    final error = persistError;
    if (error != null) throw error;
    return job.session;
  }

  @override
  Future<AppSession?> ensureReady(
    SessionConnectJob job,
    AppSession session,
  ) async {
    events.add('ensure-ready');
    ensureReadyEntered?.complete();
    await releaseEnsureReady?.future;
    return session;
  }

  @override
  Future<ResolvedLaunchMembers> resolveMember(
    SessionConnectJob job,
    AppSession session,
  ) async {
    events.add('resolve-member');
    return (
      team: job.team,
      member: resolvedMember ?? job.member!,
      cli: CliTool.claude,
    );
  }

  @override
  Future<void> installTeamRuntime(
    SessionConnectJob job,
    AppSession session,
    TeamProfile? team,
  ) async {
    events.add('install-team-runtime');
  }

  @override
  Future<void> markDeferredReady(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  ) async {
    events.add('mark-deferred-ready');
  }

  @override
  void markConnectFailed(SessionConnectJob job, String memberId) {
    failedMemberIds.add(memberId);
    if (!materializationSettled.isCompleted) materializationSettled.complete();
  }

  @override
  TerminalSession shellForLaunch(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  ) {
    events.add('acquire-shell');
    return shell;
  }

  @override
  bool isValid(SessionConnectJob job) => valid;

  @override
  void rollback(SessionConnectJob job, AppSession session) {
    rollbackCalls++;
    host.failSessionConnect(job.sessionId, 'Failed to connect session');
  }
}

class _RecordingConnector extends SessionShellConnector {
  _RecordingConnector(SessionLaunchHost host, this.events)
    : super(
        host,
        _UnusedDelegate(),
        persister: inertSessionPersistenceWriter(),
        isLocalNative: () => true,
      );

  final List<String> events;
  int connectCalls = 0;
  ConnectShellResult result = ConnectShellResult.attached;
  Object? connectorError;
  StackTrace? connectorStackTrace;
  Completer<void>? connectEntered;
  Completer<void>? releaseConnect;

  @override
  Future<ConnectShellResult> connect({
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
  }) async {
    connectCalls++;
    events.add('connect-shell');
    connectEntered?.complete();
    await releaseConnect?.future;
    final error = connectorError;
    if (error != null) {
      final stackTrace = connectorStackTrace;
      if (stackTrace != null) Error.throwWithStackTrace(error, stackTrace);
      throw error;
    }
    return result;
  }
}

class _FakeHost implements SessionLaunchHost {
  final List<String> launchErrors = <String>[];
  final List<String> finishedSessionIds = <String>[];
  final List<Object?> errors = <Object?>[];
  final List<StackTrace?> stackTraces = <StackTrace?>[];

  @override
  void failSessionConnect(
    String sessionId,
    String rawMessage, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    launchErrors.add(sessionId);
    finishedSessionIds.add(sessionId);
    errors.add(error);
    stackTraces.add(stackTrace);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedDelegate implements SessionShellConnectorDelegate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
