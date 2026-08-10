import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';

import '../../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit({this.failRename = false})
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final bool failRename;
  final prompts = <(String, String)>[];

  @override
  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt,
  ) async {
    prompts.add((sessionId, firstPrompt));
    if (failRename) throw StateError('rename failed');
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('applyLandingPromptTitleBestEffort forwards the landing prompt', () async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);

    await applyLandingPromptTitleBestEffort(
      chatCubit: chat,
      sessionId: 'sess-1',
      prompt: 'fix the title',
    );

    expect(chat.prompts, [('sess-1', 'fix the title')]);
  });

  test('applyLandingPromptTitleBestEffort swallows rename errors', () async {
    final chat = _RecordingChatCubit(failRename: true);
    addTearDown(chat.close);

    await expectLater(
      applyLandingPromptTitleBestEffort(
        chatCubit: chat,
        sessionId: 'sess-1',
        prompt: 'fix the title',
      ),
      completes,
    );

    expect(chat.prompts, [('sess-1', 'fix the title')]);
  });
}
