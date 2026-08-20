import 'message.dart';

/// Lifecycle of a todo / task item shown in chat history.
enum AiTaskStatus { pending, inProgress, completed, cancelled, unknown }

/// Maps a CLI status string to [AiTaskStatus]; anything unrecognized → unknown.
AiTaskStatus aiTaskStatusFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'pending':
      return AiTaskStatus.pending;
    case 'in_progress':
      return AiTaskStatus.inProgress;
    case 'completed':
      return AiTaskStatus.completed;
    case 'cancelled':
      return AiTaskStatus.cancelled;
    default:
      return AiTaskStatus.unknown;
  }
}

class AiTodoItem {
  const AiTodoItem({required this.content, required this.status});

  final String content;
  final AiTaskStatus status;
}

/// Parsed task / todo tool call ready for chat chrome.
sealed class AiTaskToolTarget {
  const AiTaskToolTarget({required this.toolLabel});

  /// Host-provided header label (usually the original tool name).
  final String toolLabel;
}

class AiTodoListTarget extends AiTaskToolTarget {
  const AiTodoListTarget({required super.toolLabel, required this.items});

  final List<AiTodoItem> items;
}

class AiTaskCreateTarget extends AiTaskToolTarget {
  const AiTaskCreateTarget({
    required super.toolLabel,
    required this.subject,
    this.description = '',
    this.activeForm = '',
    this.resultText,
  });

  final String subject;
  final String description;
  final String activeForm;
  final String? resultText;
}

class AiTaskUpdateTarget extends AiTaskToolTarget {
  const AiTaskUpdateTarget({
    required super.toolLabel,
    required this.status,
    this.taskId = '',
    this.argsText = '',
    this.resultText,
  });

  final String taskId;
  final AiTaskStatus status;
  final String argsText;
  final String? resultText;
}

/// One row on the floating session task board.
class AiTaskBoardItem {
  const AiTaskBoardItem({required this.subject, required this.status});

  final String subject;
  final AiTaskStatus status;
}

abstract class AiTaskToolResolver {
  AiTaskToolTarget? resolve(AiToolCallPart part);
}
