import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  late ChatCubit cubit;

  void surfaceTab(String sessionId) {
    cubit.tabStore.setActiveWorkspace('w1');
    cubit.tabStore.append(
      ChatTab(
        info: ChatTabInfo(id: sessionId, title: 'S', subtitle: ''),
        cliTeamName: '',
      ),
    );
  }

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

  test('setPodView keeps ChatTab.workbenchView in sync', () {
    surfaceTab('s1');
    cubit.ensurePodRuntime('s1');
    expect(cubit.tabStore.openTabBySessionId('s1')!.workbenchView,
        SessionWorkbenchView.chat);

    cubit.setPodView('s1', SessionWorkbenchView.terminal);

    expect(cubit.tabStore.openTabBySessionId('s1')!.workbenchView,
        SessionWorkbenchView.terminal);
    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.terminal);
  });

  test('setSessionWorkbenchView syncs a stale tab even when pod already has '
      'the view', () {
    surfaceTab('s1');
    final pod = cubit.ensurePodRuntime('s1');
    pod.setView(SessionWorkbenchView.terminal);
    // Simulate a stale transition copy left by a connect that forced Terminal
    // through the surface coordinator before the sync port existed.
    cubit.tabStore.openTabBySessionId('s1')!.workbenchView =
        SessionWorkbenchView.chat;

    cubit.setSessionWorkbenchView('s1', SessionWorkbenchView.terminal);

    expect(cubit.tabStore.openTabBySessionId('s1')!.workbenchView,
        SessionWorkbenchView.terminal);
  });
}
