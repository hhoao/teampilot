import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';
import 'package:teampilot/cubits/session/session_pod.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  late ChatCubit cubit;

  setUp(() {
    setUpTestAppStorage();
    cubit = testChatCubit(executableResolver: () => 'true');
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
}
