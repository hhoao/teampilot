import 'package:ai_message_core/ai_message_core.dart';

/// Task lifecycle statuses observed in CLI task transcripts.
enum CliTaskStatus { pending, inProgress, completed, cancelled, unknown }

/// One task in a CLI task board, derived from TaskCreate/TaskUpdate calls.
class CliTask {
  const CliTask({
    required this.taskId,
    required this.subject,
    required this.description,
    required this.activeForm,
    required this.status,
    required this.seq,
  });

  /// Server-assigned id from the TaskCreate result (may be null before the
  /// result arrives, or when the create predates the transcript window).
  final String? taskId;
  final String subject;
  final String description;
  final String activeForm;
  final CliTaskStatus status;

  /// Stable ordering for display.
  final int seq;

  CliTask copyWith({CliTaskStatus? status}) => CliTask(
    taskId: taskId,
    subject: subject,
    description: description,
    activeForm: activeForm,
    status: status ?? this.status,
    seq: seq,
  );
}

/// Immutable snapshot of all tasks derived from a transcript.
class CliTaskBoard {
  const CliTaskBoard({required this.tasks});

  final List<CliTask> tasks;

  int get totalCount => tasks.length;

  int get completedCount =>
      tasks.where((t) => t.status == CliTaskStatus.completed).length;
}

const String _kTaskCreate = 'taskcreate';
const String _kTaskUpdate = 'taskupdate';

/// Reduces a transcript into a [CliTaskBoard].
///
/// Walks assistant `AiToolCallPart`s in order: `TaskCreate` appends a pending
/// task (taskId from the correlated result); `TaskUpdate` flips a task's
/// status by id, or appends a placeholder when the id is unknown (resume
/// window where the create predates the transcript).
CliTaskBoard reduceCliTaskBoard(List<AiMessage> messages) {
  final tasks = <CliTask>[];
  var seq = 0;

  for (final message in messages) {
    if (message.role != AiRole.assistant) continue;
    for (final part in message.parts) {
      if (part is! AiToolCallPart) continue;
      final name = part.toolName.toLowerCase();
      if (name == _kTaskCreate) {
        final args = part.args ?? const <String, Object?>{};
        tasks.add(
          CliTask(
            taskId: _taskIdFromCreate(part),
            subject: _str(args['subject']),
            description: _str(args['description']),
            activeForm: _str(args['activeForm']),
            status: CliTaskStatus.pending,
            seq: seq++,
          ),
        );
      } else if (name == _kTaskUpdate) {
        final args = part.args ?? const <String, Object?>{};
        final taskId = _str(args['taskId']);
        if (taskId.isEmpty) continue;
        // TaskUpdate is a generic "update task N" tool — only a `status` arg
        // is a lifecycle transition worth rendering. Dependency/metadata
        // updates (e.g. addBlockedBy) must not create or change tasks.
        final statusRaw = _str(args['status']).trim();
        if (statusRaw.isEmpty) continue;
        final status = cliTaskStatusFromString(statusRaw);
        final index = tasks.indexWhere((t) => t.taskId == taskId);
        if (index >= 0) {
          tasks[index] = tasks[index].copyWith(status: status);
        } else {
          tasks.add(
            CliTask(
              taskId: taskId,
              subject: '',
              description: '',
              activeForm: '',
              status: status,
              seq: seq++,
            ),
          );
        }
      }
    }
  }
  return CliTaskBoard(tasks: List.unmodifiable(tasks));
}

String _str(Object? value) => value == null ? '' : '$value';

String? _taskIdFromCreate(AiToolCallPart part) {
  final result = part.result;
  if (result is Map) {
    final id = result['taskId'] ?? result['id'];
    final s = id == null ? '' : '$id';
    if (s.isNotEmpty) return s;
  }
  if (result is String) {
    // Claude Code returns e.g. "Task #1 created successfully: <subject>".
    final match = RegExp(r'Task\s*#(\d+)\s*created').firstMatch(result);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Maps a CLI status string to [CliTaskStatus]; anything unrecognized → unknown.
CliTaskStatus cliTaskStatusFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'pending':
      return CliTaskStatus.pending;
    case 'in_progress':
      return CliTaskStatus.inProgress;
    case 'completed':
      return CliTaskStatus.completed;
    case 'cancelled':
      return CliTaskStatus.cancelled;
    default:
      return CliTaskStatus.unknown;
  }
}
