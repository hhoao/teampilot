import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/launch/connect/session_connect_scheduler.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late PostFrameTestHarness postFrame;
  late RecordingExecutor executor;
  late List<String> begun;
  late List<String> finished;
  late List<String> events;
  late bool valid;
  late SessionConnectScheduler scheduler;

  setUp(() {
    postFrame = PostFrameTestHarness();
    executor = RecordingExecutor();
    begun = <String>[];
    finished = <String>[];
    events = <String>[];
    valid = true;
    scheduler = SessionConnectScheduler(
      executor: executor,
      postFrame: postFrame.scheduler,
      isJobValid: (_) => valid,
      onBegin: (sessionId) {
        begun.add(sessionId);
        events.add('begin:$sessionId');
      },
      onFinish: (sessionId) {
        finished.add(sessionId);
        events.add('finish:$sessionId');
      },
    );
  });

  test('same session/member is executed once while pending', () async {
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');
    await scheduler.enqueue(job);
    await scheduler.enqueue(job);

    expect(job.tab.membersPendingConnect, <String>{'member-1'});

    await postFrame.flush();

    expect(
      executor.jobs.map((item) => '${item.sessionId}|${item.memberId}'),
      <String>['session-1|member-1'],
    );
    expect(begun, <String>['session-1']);
    expect(finished, <String>['session-1']);
    expect(job.tab.membersPendingConnect, isEmpty);
  });

  test('different sessions can execute concurrently', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    executor.blockSession('session-1', firstStarted, releaseFirst);
    await scheduler.enqueue(
      jobFor(sessionId: 'session-1', memberId: 'member-1'),
    );
    await scheduler.enqueue(
      jobFor(sessionId: 'session-2', memberId: 'member-1'),
    );

    await postFrame.flush();

    await firstStarted.future;
    expect(executor.startedSessionIds, <String>['session-1', 'session-2']);

    releaseFirst.complete();
    await pumpEventQueue();
    expect(
      scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
      isFalse,
    );
  });

  test(
    'closed tab or changed generation is dropped before execution',
    () async {
      final job = jobFor(
        sessionId: 'session-1',
        memberId: 'member-1',
        generation: 2,
      );
      valid = false;

      await scheduler.enqueue(job);
      await postFrame.flush();

      expect(executor.jobs, isEmpty);
      expect(finished, <String>['session-1']);
    },
  );

  test('executor failure clears pending identity', () async {
    executor.error = StateError('connect failed');
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');

    await scheduler.enqueue(job);
    await postFrame.flush();

    expect(
      scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
      isFalse,
    );
  });

  test('waitForCompletion waits until the async executor finishes', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    executor.blockSession('session-1', started, release);
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');

    final completion = scheduler.enqueue(job, waitForCompletion: true);
    var completed = false;
    final observed = completion.then((_) {
      completed = true;
    });
    await postFrame.flush();
    await started.future;
    await pumpEventQueue();

    expect(completed, isFalse);
    release.complete();
    await completion;
    await observed;
    expect(completed, isTrue);
  });

  test('waitForCompletion propagates executor failures', () async {
    executor.error = StateError('connect failed');
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');

    final completion = scheduler.enqueue(job, waitForCompletion: true);
    final expectation = expectLater(completion, throwsA(isA<StateError>()));
    await postFrame.flush();

    await expectation;
    expect(
      scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
      isFalse,
    );
  });

  test(
    'cancelled queued job cannot execute or clear its replacement',
    () async {
      final cancelled = jobFor(
        sessionId: 'session-1',
        memberId: 'member-1',
        generation: 1,
      );
      final replacement = jobFor(
        sessionId: 'session-1',
        memberId: 'member-1',
        generation: 2,
      );

      await scheduler.enqueue(cancelled);
      scheduler.cancelForTab(cancelled.tab);
      await scheduler.enqueue(replacement);
      await scheduler.enqueue(replacement);

      expect(events, <String>[
        'begin:session-1',
        'finish:session-1',
        'begin:session-1',
      ]);
      expect(
        scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
        isTrue,
      );
      await postFrame.flush();

      expect(executor.jobs, hasLength(1));
      expect(executor.jobs.single.generation, 2);
      expect(
        scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
        isFalse,
      );
      expect(finished, <String>['session-1', 'session-1']);
      expect(events, <String>[
        'begin:session-1',
        'finish:session-1',
        'begin:session-1',
        'finish:session-1',
      ]);
    },
  );

  test('cancellation without replacement finishes its lifecycle', () async {
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');

    await scheduler.enqueue(job);
    scheduler.cancelForTab(job.tab);

    expect(
      scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
      isFalse,
    );
    expect(begun, <String>['session-1']);
    expect(finished, <String>['session-1']);
    expect(events, <String>['begin:session-1', 'finish:session-1']);
    expect(job.tab.membersPendingConnect, isEmpty);

    await postFrame.flush();

    expect(executor.jobs, isEmpty);
    expect(finished, <String>['session-1']);
    expect(events, <String>['begin:session-1', 'finish:session-1']);
  });

  test('cancelling a waiting job settles its completion future', () async {
    final job = jobFor(sessionId: 'session-1', memberId: 'member-1');

    final completion = scheduler.enqueue(job, waitForCompletion: true);
    scheduler.cancelForTab(job.tab);

    await completion.timeout(const Duration(milliseconds: 200));
    expect(
      scheduler.isPending(sessionId: 'session-1', memberId: 'member-1'),
      isFalse,
    );
  });
}

SessionConnectJob jobFor({
  required String sessionId,
  required String memberId,
  int generation = 1,
}) {
  final session = AppSession(
    sessionId: sessionId,
    workspaceId: 'workspace-1',
    createdAt: 1,
  );
  final member = TeamMemberConfig(id: memberId, name: memberId);
  return SessionConnectJob(
    tab: ChatTab(
      info: ChatTabInfo(id: sessionId, title: 'Session', subtitle: ''),
      cliTeamName: '',
    ),
    session: session,
    request: SessionOpenRequest(session: session),
    generation: generation,
    workspace: null,
    team: null,
    member: member,
    reason: LaunchReason.restore,
  );
}

class RecordingExecutor implements SessionConnectExecutorPort {
  final List<SessionConnectJob> jobs = <SessionConnectJob>[];
  final List<String> startedSessionIds = <String>[];
  Object? error;
  String? _blockedSessionId;
  Completer<void>? _started;
  Completer<void>? _release;

  void blockSession(
    String sessionId,
    Completer<void> started,
    Completer<void> release,
  ) {
    _blockedSessionId = sessionId;
    _started = started;
    _release = release;
  }

  @override
  Future<void> execute(SessionConnectJob job) async {
    jobs.add(job);
    startedSessionIds.add(job.sessionId);
    if (job.sessionId == _blockedSessionId) {
      _started!.complete();
      await _release!.future;
    }
    final failure = error;
    if (failure != null) throw failure;
  }
}
