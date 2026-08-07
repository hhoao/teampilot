import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';

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

  test('ensurePod seeds an idle pod and updatePod bumps phase, isolated per session', () {
    final seeded = cubit.ensurePod('s1');
    expect(seeded.phase, SessionPhase.idle);
    expect(cubit.podFor('s1'), same(seeded));

    cubit.updatePod(seeded.copyWith(phase: SessionPhase.running));
    final pod = cubit.podFor('s1');
    expect(pod!.phase, SessionPhase.running);
    expect(pod.revision, seeded.revision + 1);

    // Another session is untouched.
    expect(cubit.podFor('s2'), isNull);
    final s2 = cubit.ensurePod('s2');
    expect(s2.phase, SessionPhase.idle);
  });

  test('updatePod ignores stale revisions', () {
    final v0 = cubit.ensurePod('s1');
    final v1 = v0.copyWith(phase: SessionPhase.connecting);
    cubit.updatePod(v1);
    // An older revision (v0) must not overwrite v1.
    cubit.updatePod(v0);
    expect(cubit.podFor('s1')!.phase, SessionPhase.connecting);
  });
}
