import 'dart:async';

import 'agent_attention_state.dart';
import 'agent_status_event.dart';
import 'agent_status_normalizer.dart';
import 'ask_user_question.dart';

/// Reply for a held Claude-family AskUserQuestion `PreToolUse` HTTP hook.
final class AskUserQuestionHookReply {
  const AskUserQuestionHookReply.allow({
    required this.questions,
    required this.answers,
  }) : reject = false;

  const AskUserQuestionHookReply.reject()
    : questions = null,
      answers = null,
      reject = true;

  final List<AgentAskUserQuestion>? questions;

  /// Question text → selected label (comma-joined for multi-select).
  final Map<String, String>? answers;
  final bool reject;
}

/// Holds open Claude `PreToolUse` HTTP hooks for AskUserQuestion until the
/// chat card submits/cancels (official `updatedInput.answers` path).
final class AskUserQuestionHookGate {
  final _waiters = <String, Completer<AskUserQuestionHookReply>>{};

  /// Waits for [complete] with the same ids. Returns `null` on timeout so the
  /// handler can fall through to Claude's native TUI (`{}` response).
  Future<AskUserQuestionHookReply?> wait({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    Duration timeout = const Duration(hours: 24),
  }) async {
    final key = _key(sessionId, memberId, toolUseId);
    final existing = _waiters.remove(key);
    if (existing != null && !existing.isCompleted) {
      existing.complete(const AskUserQuestionHookReply.reject());
    }
    final completer = Completer<AskUserQuestionHookReply>();
    _waiters[key] = completer;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      final current = _waiters[key];
      if (identical(current, completer)) {
        _waiters.remove(key);
      }
    }
  }

  /// Returns true when a waiter was completed (hook still open).
  bool complete({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    required AskUserQuestionHookReply reply,
  }) {
    final completer = _waiters.remove(
      _key(sessionId, memberId, toolUseId),
    );
    if (completer == null || completer.isCompleted) return false;
    completer.complete(reply);
    return true;
  }

  bool hasWaiter({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) {
    final completer = _waiters[_key(sessionId, memberId, toolUseId)];
    return completer != null && !completer.isCompleted;
  }

  void clearSeat({required String sessionId, required String memberId}) {
    final prefix = '${sessionId.trim()}/${memberId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const AskUserQuestionHookReply.reject());
      }
    }
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}/';
    final doomed = <String>[];
    for (final key in _waiters.keys) {
      if (key.startsWith(prefix)) doomed.add(key);
    }
    for (final key in doomed) {
      final c = _waiters.remove(key);
      if (c != null && !c.isCompleted) {
        c.complete(const AskUserQuestionHookReply.reject());
      }
    }
  }

  String _key(String sessionId, String memberId, String toolUseId) =>
      '${sessionId.trim()}/${memberId.trim()}/${toolUseId.trim()}';
}

/// Keeps structured AskUserQuestion payload when a later waiting hook (often
/// PermissionRequest) arrives without `tool_input.questions`.
AgentStatusEvent preserveAskUserQuestionPayload(
  AgentStatusEvent? previous,
  AgentStatusEvent next,
) {
  if (previous == null) return next;
  if (next.askUserQuestions != null && next.askUserQuestions!.isNotEmpty) {
    return next;
  }
  final prevQs = previous.askUserQuestions;
  if (prevQs == null || prevQs.isEmpty) return next;
  if (next.state != AgentSeatAttention.waiting) return next;
  if (!isAskUserQuestionTool(previous.toolName)) return next;

  final nextTool = next.toolName?.trim() ?? '';
  if (nextTool.isNotEmpty && !isAskUserQuestionTool(nextTool)) {
    return next;
  }

  return next.copyWith(
    askUserQuestions: prevQs,
    askRequestId: next.askRequestId ?? previous.askRequestId,
    toolName: next.toolName ?? previous.toolName,
  );
}

/// Builds Claude `updatedInput.answers` from selected labels per question.
Map<String, String> askUserAnswersMap({
  required List<AgentAskUserQuestion> questions,
  required List<List<String>> answers,
}) {
  final map = <String, String>{};
  for (var i = 0; i < questions.length; i++) {
    final labels = i < answers.length ? answers[i] : const <String>[];
    if (labels.isEmpty) continue;
    map[questions[i].question] = labels.join(', ');
  }
  return map;
}

/// Serializes questions for Claude `updatedInput.questions` echo-back.
List<Map<String, Object?>> askUserQuestionsToJson(
  List<AgentAskUserQuestion> questions,
) {
  return [
    for (final q in questions)
      {
        'question': q.question,
        if (q.header != null) 'header': q.header,
        'multiSelect': q.multiSelect,
        'options': [
          for (final o in q.options)
            {
              'label': o.label,
              if (o.description != null) 'description': o.description,
            },
        ],
      },
  ];
}
