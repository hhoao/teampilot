import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

class _FakeAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

AiHistoryLoader _stubLoader() => AiHistoryLoader(
  contextBuilder: const SessionHistoryContextBuilder(),
  resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: LocalFilesystem(),
    home: '/tmp/pod-registry',
    cwd: '/tmp/pod-registry',
    appDataRoot: '/tmp/pod-registry',
    paths: AppPaths('/tmp/pod-registry'),
  ),
  registry: fakeAiHistoryRegistry(cli: CliTool.claude, adapter: _FakeAdapter()),
);

void main() {
  late ChatCubit cubit;

  setUp(() {
    setUpTestAppStorage();
    cubit = testChatCubit(executableResolver: () => 'true');
    // Wire the loader so pods own a HistoryStore in these tests.
    cubit.historyLoader = _stubLoader();
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('podFor returns null for an unknown session', () {
    expect(cubit.podFor('missing'), isNull);
  });

  test(
    'ensurePodRuntime seeds an idle pod and setPhase drives it, isolated per session',
    () {
      final seeded = cubit.ensurePodRuntime('s1');
      expect(seeded.state.phase, SessionPhase.idle);
      expect(cubit.podFor('s1')!.revision, seeded.state.revision);

      seeded.setPhase(SessionPhase.running);
      final pod = cubit.podFor('s1')!;
      expect(pod.phase, SessionPhase.running);
      expect(pod.revision, seeded.state.revision);

      // Another session is untouched.
      expect(cubit.podFor('s2'), isNull);
      final s2 = cubit.ensurePodRuntime('s2');
      expect(s2.state.phase, SessionPhase.idle);
    },
  );

  test('podFor returns the state projection, not the runtime object', () {
    final runtime = cubit.ensurePodRuntime('s1');
    final state = cubit.podFor('s1')!;
    expect(state.sessionId, 's1');
    expect(state.runtimeType, SessionPodState);
    expect(identical(state, runtime.state), isTrue);
  });

  test(
    'ensurePodRuntime creates a pod with history when a loader is wired',
    () {
      final pod = cubit.ensurePodRuntime('s1');
      expect(pod.history, isNotNull);
      final seat = pod.history!.memberSeat(sessionId: 's1', memberId: '');
      expect(seat.isClosed, isFalse);
    },
  );

  test(
    'disposePod closes history and removes the pod from the registry',
    () async {
      final pod = cubit.ensurePodRuntime('s1');
      expect(cubit.podFor('s1'), isNotNull);
      final seat = pod.history!.memberSeat(sessionId: 's1', memberId: '');

      await cubit.disposePod('s1');

      expect(cubit.podFor('s1'), isNull);
      expect(seat.isClosed, isTrue);
    },
  );

  test(
    'persistHistoryPending survives pod dispose and reloads into history',
    () async {
      const workspaceId = 'ws-1';
      const sessionId = 's1';
      const text = 'launch this prompt';

      final record = await cubit.persistHistoryPending(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: '',
        text: text,
      );
      expect(record, isNotNull);
      expect(record!.text, text);

      final store = FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      );
      expect(await store.load(workspaceId, sessionId), [record]);

      await cubit.disposePod(sessionId);

      cubit.ensurePodRuntime(sessionId);
      final reloaded = cubit
          .podRuntime(sessionId)!
          .history!
          .memberSeat(sessionId: sessionId, memberId: '');
      await reloaded.hydratePendingUsers(
        store: store,
        workspaceId: workspaceId,
        sessionId: sessionId,
      );

      expect(reloaded.runtime.messages.single.id, record.id);
      expect(
        reloaded.pendingDeliveryStatusFor(record.id),
        FailedMessageStatus.failed,
      );
      expect(reloaded.state.awaitingAssistant, isFalse);
    },
  );

  test(
    'persistHistoryPending reuses one pending bubble for a delivery id',
    () async {
      const workspaceId = 'ws-1';
      const sessionId = 's1';
      const deliveryId = 'teamgen-kickoff-123';
      const text = 'Build the optimal team';

      final first = await cubit.persistHistoryPending(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: '',
        text: text,
        deliveryId: deliveryId,
      );
      final repeated = await cubit.persistHistoryPending(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: '',
        text: text,
        deliveryId: deliveryId,
      );

      expect(repeated!.id, first!.id);
      expect(repeated.deliveryId, deliveryId);
      expect(
        await FailedMessageStore(
          fs: AppStorage.fs,
          rootPath: AppStorage.appDataRoot,
        ).load(workspaceId, sessionId),
        [first],
      );
      expect(
        cubit
            .podRuntime(sessionId)!
            .history!
            .memberSeat(sessionId: sessionId, memberId: '')
            .runtime
            .messages,
        hasLength(1),
      );
    },
  );

  test('clearHistoryPending removes a delivered landing bubble', () async {
    const workspaceId = 'ws-1';
    const sessionId = 's1';
    const text = 'landing delivered';

    final record = await cubit.persistHistoryPending(
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: '',
      text: text,
    );
    expect(record, isNotNull);

    await cubit.clearHistoryPending(
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: '',
      recordId: record!.id,
    );

    final seat = cubit
        .podRuntime(sessionId)!
        .history!
        .memberSeat(sessionId: sessionId, memberId: '');
    expect(seat.runtime.messages, isEmpty);
    expect(
      await FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      ).load(workspaceId, sessionId),
      isEmpty,
    );
  });

  test(
    'markHistoryPendingFailed keeps the bubble for landing delivery failure',
    () async {
      const workspaceId = 'ws-1';
      const sessionId = 's1';
      const text = 'retry after connect failure';

      final record = await cubit.persistHistoryPending(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: '',
        text: text,
      );
      expect(record, isNotNull);

      await cubit.markHistoryPendingFailed(
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: '',
        record: record!,
      );

      final seat = cubit
          .podRuntime(sessionId)!
          .history!
          .memberSeat(sessionId: sessionId, memberId: '');
      expect(
        seat.pendingDeliveryStatusFor(record.id),
        FailedMessageStatus.failed,
      );
      expect(seat.runtime.messages.single.id, record.id);
    },
  );
}
