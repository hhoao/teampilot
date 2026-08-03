import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/ask_user_question_answer_service.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

class _FakeShell extends TerminalSession {
  _FakeShell({required this.connected})
    : super(
        executable: 'unused',
        validateLaunch: false,
        parseExecutable: false,
        launchController: TerminalLaunchController(
          engine: TerminalEngine(config: TerminalConfig.defaults()),
          activityTracker: TerminalActivityTracker(),
          defaultExecutable: 'unused',
          startupDeadline: const Duration(seconds: 5),
          confirmFallback: const Duration(milliseconds: 50),
          validateLaunch: false,
        ),
      );

  final bool connected;

  @override
  bool get isConnected => connected;
}

void main() {
  test('answer writes selection digit, waits, then Enter', () async {
    final writes = <String>[];
    final gaps = <Duration>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async => gaps.add(d),
    );
    await service.answer(shell: _FakeShell(connected: true), optionIndex: 1);

    // Option index 1 → picker digit "2"; trailing Enter after the settle gap.
    expect(writes, ['2', '\r']);
    expect(gaps, [AskUserQuestionAnswerService.selectionToSubmitGap]);
  });

  test('no-op when shell disconnected or null', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
      delay: (d) async {},
    );
    await service.answer(
      shell: _FakeShell(connected: false),
      optionIndex: 1,
    );
    expect(writes, isEmpty);

    await service.answer(shell: null, optionIndex: 1);
    expect(writes, isEmpty);
  });

  test('cancel writes Esc', () async {
    final writes = <String>[];
    final service = AskUserQuestionAnswerService(
      writePty: (_, text) => writes.add(text),
    );
    await service.cancel(shell: _FakeShell(connected: true));
    expect(writes, ['\x1b']);
  });
}
