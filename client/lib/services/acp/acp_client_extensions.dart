import 'package:ai_message_core/ai_message_core.dart';

import '../agent_status/agent_permission_request.dart';
import '../agent_status/ask_user_question.dart';

/// Cursor ACP blocking methods the client must answer.
const cursorAskQuestionMethod = 'cursor/ask_question';
const cursorCreatePlanMethod = 'cursor/create_plan';

/// Cursor ACP notification methods (no reply).
const cursorUpdateTodosMethod = 'cursor/update_todos';
const cursorTaskMethod = 'cursor/task';
const cursorGenerateImageMethod = 'cursor/generate_image';

/// A blocking client request waiting on a single-slot hold.
sealed class AcpPendingClientRequest {
  const AcpPendingClientRequest();
}

final class AcpPendingPermission extends AcpPendingClientRequest {
  const AcpPendingPermission(this.request);
  final AgentPermissionRequest request;
}

final class AcpPendingAsk extends AcpPendingClientRequest {
  const AcpPendingAsk({required this.questions, required this.toolCallId});
  final List<AiAskUserQuestion> questions;
  final String toolCallId;
}

final class AcpPendingPlan extends AcpPendingClientRequest {
  const AcpPendingPlan({
    required this.toolCallId,
    required this.planText,
    this.name,
    this.overview,
  });
  final String toolCallId;
  final String planText;
  final String? name;
  final String? overview;
}

/// User (or timeout) answer for a held blocking request.
sealed class AcpHoldReply {
  const AcpHoldReply();
}

/// Shared stale / timeout / dispose value. Ask and plan encoders map it to
/// `{outcome: cancelled}`; permission treats it like reject.
final class AcpCancelledHoldReply extends AcpHoldReply {
  const AcpCancelledHoldReply();
}

final class AcpPermissionHoldReply extends AcpHoldReply {
  const AcpPermissionHoldReply({required this.kind, this.always});
  final AgentPermissionReplyKind kind;
  final AgentPermissionAlwaysOption? always;
}

final class AcpAskHoldReply extends AcpHoldReply {
  const AcpAskHoldReply.answered(this.submission)
    : skipped = false,
      cancelled = false;
  const AcpAskHoldReply.skipped()
    : submission = null,
      skipped = true,
      cancelled = false;
  const AcpAskHoldReply.cancelled()
    : submission = null,
      skipped = false,
      cancelled = true;
  final AiAskUserSubmission? submission;
  final bool skipped;
  final bool cancelled;
}

final class AcpPlanHoldReply extends AcpHoldReply {
  const AcpPlanHoldReply.accepted()
    : rejected = false,
      cancelled = false,
      reason = null;
  const AcpPlanHoldReply.rejected([this.reason])
    : rejected = true,
      cancelled = false;
  const AcpPlanHoldReply.cancelled()
    : rejected = false,
      cancelled = true,
      reason = null;
  final bool rejected;
  final bool cancelled;
  final String? reason;
}

/// Parsed Cursor ACP notification payload.
sealed class AcpExtensionNotification {
  const AcpExtensionNotification();
}

/// One todo on the wire. [id] is required for merge-by-id; [status] is the
/// raw Cursor string so unknown values survive until fold.
final class AcpTodoItem {
  const AcpTodoItem({
    required this.id,
    required this.content,
    required this.status,
  });
  final String id;
  final String content;
  final String status;
}

final class AcpTodoListNotification extends AcpExtensionNotification {
  const AcpTodoListNotification({required this.todos, required this.merge});
  final List<AcpTodoItem> todos;
  final bool merge;
}

final class AcpTaskNotification extends AcpExtensionNotification {
  const AcpTaskNotification({
    required this.toolCallId,
    required this.description,
    required this.subagentType,
  });
  final String toolCallId;
  final String description;
  final String subagentType;
}

final class AcpGeneratedImageNotification extends AcpExtensionNotification {
  const AcpGeneratedImageNotification({
    required this.toolCallId,
    required this.description,
    this.filePath,
  });
  final String toolCallId;
  final String description;
  final String? filePath;
}

/// Parses a Cursor blocking JSON-RPC request. Returns null when the method
/// is unknown or the payload is not a holdable ask/plan.
AcpPendingClientRequest? parseCursorBlockingRequest(
  String method,
  Map<String, Object?> params,
) {
  switch (method) {
    case cursorAskQuestionMethod:
      return _parseAsk(params);
    case cursorCreatePlanMethod:
      return _parsePlan(params);
    default:
      return null;
  }
}

/// Encodes a hold reply as Cursor's nested `{outcome: {outcome, …}}` result.
///
/// Unknown methods and mismatched reply types encode as cancelled so a
/// registered blocking request is never left unanswered.
Map<String, Object?> encodeCursorBlockingReply(
  String method,
  AcpHoldReply reply, {
  required List<AiAskUserQuestion> questions,
}) {
  switch (method) {
    case cursorAskQuestionMethod:
      return _encodeAsk(reply, questions);
    case cursorCreatePlanMethod:
      return _encodePlan(reply);
    default:
      return _cancelledResult;
  }
}

/// Parses a Cursor notification. Returns null for unknown methods or
/// payloads missing required fields.
AcpExtensionNotification? parseCursorNotification(
  String method,
  Map<String, Object?> params,
) {
  switch (method) {
    case cursorUpdateTodosMethod:
      return _parseTodos(params);
    case cursorTaskMethod:
      return _parseTask(params);
    case cursorGenerateImageMethod:
      return _parseImage(params);
    default:
      return null;
  }
}

AcpPendingAsk? _parseAsk(Map<String, Object?> params) {
  final questions = parseQuestionsList(params['questions']);
  if (questions == null) return null;
  return AcpPendingAsk(
    questions: questions,
    toolCallId: _nonEmptyString(params['toolCallId']) ?? '',
  );
}

AcpPendingPlan? _parsePlan(Map<String, Object?> params) {
  final planText = _nonEmptyString(params['plan']);
  if (planText == null) return null;
  return AcpPendingPlan(
    toolCallId: _nonEmptyString(params['toolCallId']) ?? '',
    planText: planText,
    name: _nonEmptyString(params['name']),
    overview: _nonEmptyString(params['overview']),
  );
}

AcpTodoListNotification _parseTodos(Map<String, Object?> params) {
  final raw = params['todos'];
  final todos = <AcpTodoItem>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      todos.add(
        AcpTodoItem(
          id: _stringify(item['id']),
          content: _stringify(item['content']),
          status: _stringify(item['status']),
        ),
      );
    }
  }
  return AcpTodoListNotification(todos: todos, merge: params['merge'] == true);
}

AcpTaskNotification? _parseTask(Map<String, Object?> params) {
  final toolCallId = _nonEmptyString(params['toolCallId']);
  final description = _nonEmptyString(params['description']);
  if (toolCallId == null || description == null) return null;
  return AcpTaskNotification(
    toolCallId: toolCallId,
    description: description,
    subagentType: _subagentType(params['subagentType']) ?? '',
  );
}

AcpGeneratedImageNotification? _parseImage(Map<String, Object?> params) {
  final toolCallId = _nonEmptyString(params['toolCallId']);
  final description = _nonEmptyString(params['description']);
  if (toolCallId == null || description == null) return null;
  return AcpGeneratedImageNotification(
    toolCallId: toolCallId,
    description: description,
    filePath: _nonEmptyString(params['filePath']),
  );
}

Map<String, Object?> _encodeAsk(
  AcpHoldReply reply,
  List<AiAskUserQuestion> questions,
) {
  if (reply is AcpCancelledHoldReply) return _cancelledResult;
  if (reply is! AcpAskHoldReply) return _cancelledResult;
  if (reply.cancelled) return _cancelledResult;
  if (reply.skipped) {
    return _wrapOutcome(const {'outcome': 'skipped'});
  }
  final submission = reply.submission;
  if (submission == null) return _cancelledResult;
  final answers = <Map<String, Object?>>[
    for (var i = 0; i < questions.length; i++)
      {
        'questionId': questions[i].id ?? 'q$i',
        'selectedOptionIds': _selectedOptionIds(questions[i], submission, i),
      },
  ];
  return _wrapOutcome({'outcome': 'answered', 'answers': answers});
}

Map<String, Object?> _encodePlan(AcpHoldReply reply) {
  if (reply is AcpCancelledHoldReply) return _cancelledResult;
  if (reply is! AcpPlanHoldReply) return _cancelledResult;
  if (reply.cancelled) return _cancelledResult;
  if (reply.rejected) {
    final reason = reply.reason;
    return _wrapOutcome({
      'outcome': 'rejected',
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }
  return _wrapOutcome(const {'outcome': 'accepted'});
}

List<String> _selectedOptionIds(
  AiAskUserQuestion question,
  AiAskUserSubmission submission,
  int index,
) {
  if (index >= submission.answers.length) return const [];
  return [
    for (final token in submission.answers[index])
      _optionIdFor(question, token),
  ];
}

String _optionIdFor(AiAskUserQuestion question, String token) {
  for (final option in question.options) {
    if (option.label == token) return option.id ?? option.label;
  }
  for (final option in question.options) {
    if (option.id == token) return option.id!;
  }
  return token;
}

String? _subagentType(Object? raw) {
  if (raw is String) return _nonEmptyString(raw);
  if (raw is! Map) return null;
  final custom = raw['custom'];
  if (custom is String) return _nonEmptyString(custom);
  for (final value in raw.values) {
    if (value is String) {
      final trimmed = _nonEmptyString(value);
      if (trimmed != null) return trimmed;
    }
  }
  return null;
}

const _cancelledResult = {
  'outcome': {'outcome': 'cancelled'},
};

Map<String, Object?> _wrapOutcome(Map<String, Object?> inner) => {
  'outcome': inner,
};

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString();
}
