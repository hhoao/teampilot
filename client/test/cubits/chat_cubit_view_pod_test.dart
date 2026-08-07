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

  test('setSessionWorkbenchView writes the pod view', () {
    cubit.ensurePodRuntime('s1');
    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.chat);

    cubit.setSessionWorkbenchView('s1', SessionWorkbenchView.terminal);

    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.terminal);
  });

  test('setPodView (host port) writes the pod view', () {
    cubit.ensurePodRuntime('s1');
    cubit.setPodView('s1', SessionWorkbenchView.terminal);
    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.terminal);
  });
}
