import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../agent_status/ask_user_answer_pending_store.dart';
import '../cli/registry/capabilities/ask_user_question_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'member_turn_interrupt_service.dart';
import 'terminal_session.dart';

sealed class AskUserAnswerResult {
  const AskUserAnswerResult();
}

final class AskUserAnswerOk extends AskUserAnswerResult {
  const AskUserAnswerOk();
}

final class AskUserAnswerFailed extends AskUserAnswerResult {
  const AskUserAnswerFailed(this.reason);
  final String reason;
}

/// Facade that answers / cancels AskUserQuestion by CLI capability:
/// PTY digit inject for [AskUserAnswerKind.ptyPicker], pending store for
/// [AskUserAnswerKind.pluginSdkReply].
final class AskUserQuestionAnswerService {
  AskUserQuestionAnswerService({
    MemberPtyWriter? writePty,
    Future<void> Function(Duration delay)? delay,
    CliToolRegistry? registry,
    AskUserAnswerPendingStore? store,
  }) : _writePty = writePty ?? ((shell, text) => shell.input.writeToPty(text)),
       _delay = delay ?? Future<void>.delayed,
       _registry = registry ?? CliToolRegistry.builtIn(),
       _store = store ?? AskUserAnswerPendingStore();

  final MemberPtyWriter _writePty;
  final Future<void> Function(Duration delay) _delay;
  final CliToolRegistry _registry;
  final AskUserAnswerPendingStore _store;

  /// Gap between the selection digit and the trailing Enter, letting the
  /// picker close in raw mode before the Enter lands on the prompt line.
  static const Duration selectionToSubmitGap = Duration(milliseconds: 120);

  Future<AskUserAnswerResult> answer({
    required CliTool cli,
    required String sessionId,
    required String memberId,
    required TerminalSession? shell,
    required String? askRequestId,
    int? optionIndex,
    List<List<String>>? answers,
  }) async {
    final kind = _answerKind(cli);
    switch (kind) {
      case AskUserAnswerKind.ptyPicker:
        return _answerPty(shell: shell, optionIndex: optionIndex);
      case AskUserAnswerKind.pluginSdkReply:
        return _answerPending(
          sessionId: sessionId,
          memberId: memberId,
          askRequestId: askRequestId,
          answers: answers,
        );
      case AskUserAnswerKind.none:
        return const AskUserAnswerFailed('unsupported');
    }
  }

  Future<AskUserAnswerResult> cancel({
    required CliTool cli,
    required String sessionId,
    required String memberId,
    required TerminalSession? shell,
    required String? askRequestId,
  }) async {
    final kind = _answerKind(cli);
    switch (kind) {
      case AskUserAnswerKind.ptyPicker:
        return _cancelPty(shell: shell);
      case AskUserAnswerKind.pluginSdkReply:
        return _cancelPending(
          sessionId: sessionId,
          memberId: memberId,
          askRequestId: askRequestId,
        );
      case AskUserAnswerKind.none:
        return const AskUserAnswerFailed('unsupported');
    }
  }

  AskUserAnswerKind _answerKind(CliTool cli) {
    return _registry.capability<AskUserQuestionCapability>(cli)?.answerKind ??
        AskUserAnswerKind.none;
  }

  Future<AskUserAnswerResult> _answerPty({
    required TerminalSession? shell,
    required int? optionIndex,
  }) async {
    if (optionIndex == null || optionIndex < 0) {
      return const AskUserAnswerFailed('missing_option_index');
    }
    if (!_isConnected(shell)) {
      return const AskUserAnswerFailed('terminal_disconnected');
    }
    _writePty(shell!, '${optionIndex + 1}');
    await _delay(selectionToSubmitGap);
    _writePty(shell, '\r');
    return const AskUserAnswerOk();
  }

  Future<AskUserAnswerResult> _cancelPty({
    required TerminalSession? shell,
  }) async {
    if (!_isConnected(shell)) {
      return const AskUserAnswerFailed('terminal_disconnected');
    }
    _writePty(shell!, '\x1b');
    return const AskUserAnswerOk();
  }

  AskUserAnswerResult _answerPending({
    required String sessionId,
    required String memberId,
    required String? askRequestId,
    required List<List<String>>? answers,
  }) {
    final requestId = askRequestId?.trim() ?? '';
    if (requestId.isEmpty) {
      return const AskUserAnswerFailed('missing_request_id');
    }
    if (answers == null) {
      return const AskUserAnswerFailed('missing_answers');
    }
    _store.put(
      sessionId: sessionId,
      memberId: memberId,
      entry: AskUserAnswerPendingEntry(
        requestId: requestId,
        answers: answers,
      ),
    );
    return const AskUserAnswerOk();
  }

  AskUserAnswerResult _cancelPending({
    required String sessionId,
    required String memberId,
    required String? askRequestId,
  }) {
    final requestId = askRequestId?.trim() ?? '';
    if (requestId.isEmpty) {
      return const AskUserAnswerFailed('missing_request_id');
    }
    _store.put(
      sessionId: sessionId,
      memberId: memberId,
      entry: AskUserAnswerPendingEntry(requestId: requestId, reject: true),
    );
    return const AskUserAnswerOk();
  }

  bool _isConnected(TerminalSession? shell) {
    if (shell == null || !shell.isConnected) {
      appLogger.d('[ask-user-question] skip — shell not connected');
      return false;
    }
    return true;
  }
}
