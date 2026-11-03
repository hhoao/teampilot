import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';

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

  test('begin publishes the trimmed landing prompt and clear drops it', () {
    expect(cubit.state.pendingLandingPrompts, isEmpty);

    cubit.beginPendingLandingPrompt(sessionId: 's1', text: '  hello  ');
    expect(cubit.state.pendingLandingPrompts, {'s1': 'hello'});

    cubit.clearPendingLandingPrompt('s1');
    expect(cubit.state.pendingLandingPrompts, isEmpty);
  });

  test('begin ignores blank input and does not re-emit for the same text', () {
    cubit.beginPendingLandingPrompt(sessionId: 's1', text: '   ');
    expect(cubit.state.pendingLandingPrompts, isEmpty);

    cubit.beginPendingLandingPrompt(sessionId: 's1', text: 'hi');
    final after = cubit.state;
    cubit.beginPendingLandingPrompt(sessionId: 's1', text: 'hi');
    expect(identical(cubit.state, after), isTrue);
  });

  test('clear on an unknown session is a no-op', () {
    final before = cubit.state;
    cubit.clearPendingLandingPrompt('missing');
    expect(identical(cubit.state, before), isTrue);
  });
}
