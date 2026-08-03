import '../../utils/logging/logger.dart';
import 'member_turn_interrupt_service.dart';
import 'terminal_session.dart';

/// Injects keystrokes that answer / cancel a Claude-family AskUserQuestion
/// picker over the seat PTY. Single-select only (see plan): a bare selection
/// digit selects immediately in raw mode and falls back to line input + Enter
/// in cooked mode, so the trailing `\r` covers both.
final class AskUserQuestionAnswerService {
  AskUserQuestionAnswerService({
    MemberPtyWriter? writePty,
    Future<void> Function(Duration delay)? delay,
  }) : _writePty = writePty ?? ((shell, text) => shell.input.writeToPty(text)),
       _delay = delay ?? Future<void>.delayed;

  final MemberPtyWriter _writePty;
  final Future<void> Function(Duration delay) _delay;

  /// Gap between the selection digit and the trailing Enter, letting the
  /// picker close in raw mode before the Enter lands on the prompt line.
  static const Duration selectionToSubmitGap = Duration(milliseconds: 120);

  /// Selects the authored option at [optionIndex] (0-based) in the picker.
  Future<void> answer({
    required TerminalSession? shell,
    required int optionIndex,
  }) async {
    if (optionIndex < 0 || !_isConnected(shell)) return;
    _writePty(shell!, '${optionIndex + 1}');
    await _delay(selectionToSubmitGap);
    _writePty(shell, '\r');
  }

  /// Cancels the picker (Esc → the CLI resolves the tool as declined).
  Future<void> cancel({required TerminalSession? shell}) async {
    if (!_isConnected(shell)) return;
    _writePty(shell!, '\x1b');
  }

  bool _isConnected(TerminalSession? shell) {
    if (shell == null || !shell.isConnected) {
      appLogger.d('[ask-user-question] skip — shell not connected');
      return false;
    }
    return true;
  }
}
