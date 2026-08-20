import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../agent_status/ask_user_question.dart';
import 'edit_codecs/tool_args.dart';

/// Parses TaskCreate / TaskUpdate / TodoWrite into [AiTaskToolTarget].
class TranscriptAiTaskToolResolver implements AiTaskToolResolver {
  const TranscriptAiTaskToolResolver({this.contentById = const {}});

  /// Prior todo text by id, used to fill Cursor merge payloads.
  final Map<String, String> contentById;

  @override
  AiTaskToolTarget? resolve(AiToolCallPart part) {
    switch (part.toolName.toLowerCase()) {
      case 'todowrite':
        return _todoList(part);
      case 'taskcreate':
        return _create(part);
      case 'taskupdate':
        return _update(part);
      default:
        return null;
    }
  }

  AiTodoListTarget _todoList(AiToolCallPart part) {
    final args = toolCallArgsMap(part) ?? const <String, Object?>{};
    final raw = args['todos'];
    final items = <AiTodoItem>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        items.add(
          AiTodoItem(
            content: _todoContent(item),
            status: aiTaskStatusFromString(_stringify(item['status'])),
          ),
        );
      }
    }
    return AiTodoListTarget(toolLabel: part.toolName, items: items);
  }

  String _todoContent(Map<dynamic, dynamic> item) {
    final local = _stringify(item['content']).trim();
    if (local.isNotEmpty) return local;
    final id = _stringify(item['id']).trim();
    if (id.isEmpty) return '';
    return contentById[id] ?? '';
  }

  AiTaskCreateTarget _create(AiToolCallPart part) {
    final args = toolCallArgsMap(part) ?? const <String, Object?>{};
    final result = part.result;
    return AiTaskCreateTarget(
      toolLabel: part.toolName,
      subject: _stringify(args['subject']).trim(),
      description: _stringify(args['description']).trim(),
      activeForm: _stringify(args['activeForm']).trim(),
      resultText: result == null ? null : _stringify(result),
    );
  }

  AiTaskUpdateTarget _update(AiToolCallPart part) {
    final args = toolCallArgsMap(part) ?? const <String, Object?>{};
    final result = part.result;
    return AiTaskUpdateTarget(
      toolLabel: part.toolName,
      taskId: _stringify(args['taskId']).trim(),
      status: aiTaskStatusFromString(_stringify(args['status'])),
      argsText: _stringify(part.args ?? args),
      resultText: result == null ? null : _stringify(result),
    );
  }
}

/// Parses ask-user tool calls into [AiAskUserTarget].
class TranscriptAiAskUserResolver implements AiAskUserResolver {
  const TranscriptAiAskUserResolver();

  static const toolNames = {
    'askuserquestion',
    'ask_user_question',
    'ask_user',
    'askquestion',
    'question',
  };

  @override
  AiAskUserTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;
    final questions = askUserQuestionsFromPart(part);
    if (questions == null) return null;
    final answers = parseAskUserAnswers(
      questions: questions,
      result: part.result,
    );
    return AiAskUserTarget(
      items: [
        for (var i = 0; i < questions.length; i++)
          AiAskUserItem(
            question: questions[i].question,
            answer: i < answers.length ? answers[i] : null,
          ),
      ],
      asking:
          part.status == AiToolCallStatus.running ||
          part.status == AiToolCallStatus.incomplete,
    );
  }
}

/// Questions encoded on a history tool-call part, or null when unparseable.
List<AgentAskUserQuestion>? askUserQuestionsFromPart(AiToolCallPart part) {
  final fromArgs = parseAskUserQuestions(part.args);
  if (fromArgs != null) return fromArgs;
  final text = part.argsText?.trim() ?? '';
  if (text.isEmpty) return null;
  try {
    return parseAskUserQuestions(jsonDecode(text));
  } on Object {
    return null;
  }
}

/// Looks up a workflow run attachment by tool-call id.
class AttachmentAiWorkflowResolver implements AiWorkflowResolver {
  const AttachmentAiWorkflowResolver({required this.attachments});

  final Map<String, AiSubagentAttachment> attachments;

  @override
  AiWorkflowTarget? resolve(AiToolCallPart part) {
    if (part.toolName.toLowerCase() != 'workflow') return null;
    return AiWorkflowTarget(workflow: attachments[part.toolCallId]?.workflow);
  }
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
