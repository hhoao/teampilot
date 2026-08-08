import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/session_phase.dart';

import '../../support/post_frame_test_harness.dart';

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

  test('begin→finish drives pod phase connecting→running', () {
    cubit.ensurePodRuntime('s1');
    cubit.beginSessionConnect('s1');
    expect(cubit.podFor('s1')!.phase, SessionPhase.connecting);
    cubit.finishSessionConnect('s1');
    expect(cubit.podFor('s1')!.phase, SessionPhase.running);
  });

  test('failSessionConnect drives pod to error with launchError, not running', () {
    cubit.ensurePodRuntime('s1');
    cubit.beginSessionConnect('s1');
    cubit.failSessionConnect('s1', 'boom');
    final pod = cubit.podFor('s1')!;
    expect(pod.phase, SessionPhase.error);
    expect(pod.launchError, 'boom');
  });

  test('phases are isolated per session', () {
    cubit.ensurePodRuntime('s1');
    cubit.ensurePodRuntime('s2');
    cubit.beginSessionConnect('s1');
    expect(cubit.podFor('s1')!.phase, SessionPhase.connecting);
    expect(cubit.podFor('s2')!.phase, SessionPhase.idle);
    cubit.failSessionConnect('s1', 'boom');
    expect(cubit.podFor('s1')!.phase, SessionPhase.error);
    expect(cubit.podFor('s2')!.phase, SessionPhase.idle);
  });

  test('pending materialization sets hasConnectingSession without a real pod', () {
    cubit.beginSessionConnect('pending');
    expect(cubit.hasConnectingSession, isTrue);
    expect(cubit.podFor('pending'), isNull, reason: 'no real pod for pending');
    cubit.finishSessionConnect('pending');
    expect(cubit.hasConnectingSession, isFalse);
  });

  test('isSessionConnecting follows a real session pod phase', () {
    cubit.ensurePodRuntime('s1');
    expect(cubit.isSessionConnecting('s1'), isFalse);
    cubit.beginSessionConnect('s1');
    expect(cubit.isSessionConnecting('s1'), isTrue);
    cubit.finishSessionConnect('s1');
    expect(cubit.isSessionConnecting('s1'), isFalse);
  });
}
