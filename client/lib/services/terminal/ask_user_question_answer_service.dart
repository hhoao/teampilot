import '../../models/team_config.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../agent_status/ask_user_answer_pending_store.dart';
import '../agent_status/ask_user_question.dart';
import '../agent_status/ask_user_question_hook_gate.dart';
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
/// Claude-family prefers held PreToolUse hook reply ([AskUserQuestionHookGate]),
/// then PTY digit inject; OpenCode uses the pending store.
final class AskUserQuestionAnswerService {
  AskUserQuestionAnswerService({
    MemberPtyWriter? writePty,
    Future<void> Function(Duration delay)? delay,
    CliToolRegistry? registry,
    AskUserAnswerPendingStore? store,
    AskUserQuestionHookGate? hookGate,
  }) : _writePty = writePty ?? ((shell, text) => shell.input.writeToPty(text)),
       _delay = delay ?? Future<void>.delayed,
       _registry = registry ?? CliToolRegistry.builtIn(),
       _store = store ?? AskUserAnswerPendingStore(),
       _hookGate = hookGate;

  final MemberPtyWriter _writePty;
  final Future<void> Function(Duration delay) _delay;
  final CliToolRegistry _registry;
  final AskUserAnswerPendingStore _store;
  final AskUserQuestionHookGate? _hookGate;

  /// Gap between the selection digit and the trailing Enter, letting the
  /// picker close in raw mode before the Enter lands on the prompt line.
  static const Duration selectionToSubmitGap = Duration(milliseconds: 120);

  /// CSI CUF — Claude AskUserQuestion multi-question pager "next".
  static const String nextQuestionKey = '\x1b[C';

  Future<AskUserAnswerResult> answer({
    required CliTool cli,
    required String sessionId,
    required String memberId,
    required TerminalSession? shell,
    required String? askRequestId,
    int? optionIndex,
    List<int>? optionIndices,
    List<List<String>>? answers,
    String? freeText,
    List<String?>? freeTexts,
    List<AgentAskUserQuestion>? questions,
  }) async {
    final kind = _answerKind(cli);
    switch (kind) {
      case AskUserAnswerKind.ptyPicker:
        if (_completeHookAllow(
          sessionId: sessionId,
          memberId: memberId,
          askRequestId: askRequestId,
          questions: questions,
          answers: answers,
        )) {
          return const AskUserAnswerOk();
        }
        return _answerPty(
          shell: shell,
          optionIndex: optionIndex,
          optionIndices: optionIndices,
          freeText: freeText,
          freeTexts: freeTexts,
        );
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
        if (_completeHookReject(
          sessionId: sessionId,
          memberId: memberId,
          askRequestId: askRequestId,
        )) {
          return const AskUserAnswerOk();
        }
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

  bool _completeHookAllow({
    required String sessionId,
    required String memberId,
    required String? askRequestId,
    required List<AgentAskUserQuestion>? questions,
    required List<List<String>>? answers,
  }) {
    final gate = _hookGate;
    final toolUseId = askRequestId?.trim() ?? '';
    if (gate == null ||
        toolUseId.isEmpty ||
        questions == null ||
        questions.isEmpty ||
        answers == null) {
      return false;
    }
    final map = askUserAnswersMap(questions: questions, answers: answers);
    if (map.isEmpty) return false;
    return gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
      reply: AskUserQuestionHookReply.allow(
        questions: questions,
        answers: map,
      ),
    );
  }

  bool _completeHookReject({
    required String sessionId,
    required String memberId,
    required String? askRequestId,
  }) {
    final gate = _hookGate;
    final toolUseId = askRequestId?.trim() ?? '';
    if (gate == null || toolUseId.isEmpty) return false;
    return gate.complete(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
      reply: const AskUserQuestionHookReply.reject(),
    );
  }

  Future<AskUserAnswerResult> _answerPty({
    required TerminalSession? shell,
    required int? optionIndex,
    List<int>? optionIndices,
    String? freeText,
    List<String?>? freeTexts,
  }) async {
    final indices = optionIndices ??
        (optionIndex == null ? null : <int>[optionIndex]);
    if (indices == null || indices.isEmpty) {
      return const AskUserAnswerFailed('missing_option_index');
    }
    if (indices.any((i) => i < 0)) {
      return const AskUserAnswerFailed('missing_option_index');
    }
    if (!_isConnected(shell)) {
      return const AskUserAnswerFailed('terminal_disconnected');
    }

    for (var i = 0; i < indices.length; i++) {
      if (i > 0) {
        _writePty(shell!, nextQuestionKey);
        await _delay(selectionToSubmitGap);
      }
      final text = _freeTextAt(i, freeText: freeText, freeTexts: freeTexts);
      _writePty(shell!, '${indices[i] + 1}');
      await _delay(selectionToSubmitGap);
      if (text != null && text.isNotEmpty) {
        // Claude TUI "Other" — digit focuses freeform, then type.
        _writePty(shell, text);
        await _delay(selectionToSubmitGap);
        if (i < indices.length - 1) {
          // Leave the Other field before advancing the pager.
          _writePty(shell, '\t');
          await _delay(selectionToSubmitGap);
        }
      }
    }
    _writePty(shell!, '\r');
    return const AskUserAnswerOk();
  }

  String? _freeTextAt(
    int index, {
    required String? freeText,
    required List<String?>? freeTexts,
  }) {
    if (freeTexts != null && index < freeTexts.length) {
      return freeTexts[index]?.trim();
    }
    if (index == 0) return freeText?.trim();
    return null;
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
