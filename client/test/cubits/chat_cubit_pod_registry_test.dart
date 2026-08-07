import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
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
  registry: fakeAiHistoryRegistry(
    cli: CliTool.claude,
    adapter: _FakeAdapter(),
  ),
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

  test('ensurePodRuntime seeds an idle pod and setPhase drives it, isolated per session', () {
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
  });

  test('podFor returns the state projection, not the runtime object', () {
    final runtime = cubit.ensurePodRuntime('s1');
    final state = cubit.podFor('s1')!;
    expect(state.sessionId, 's1');
    expect(state.runtimeType, SessionPodState);
    expect(identical(state, runtime.state), isTrue);
  });

  test('ensurePodRuntime creates a pod with history when a loader is wired', () {
    final pod = cubit.ensurePodRuntime('s1');
    expect(pod.history, isNotNull);
    final seat = pod.history!.memberSeat(sessionId: 's1', memberId: '');
    expect(seat.isClosed, isFalse);
  });

  test('disposePod closes history and removes the pod from the registry', () async {
    final pod = cubit.ensurePodRuntime('s1');
    expect(cubit.podFor('s1'), isNotNull);
    final seat = pod.history!.memberSeat(sessionId: 's1', memberId: '');

    await cubit.disposePod('s1');

    expect(cubit.podFor('s1'), isNull);
    expect(seat.isClosed, isTrue);
  });
}
