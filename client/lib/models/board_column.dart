import '../services/team_bus/tasks/team_task.dart';

/// Read-only board lanes. Collapses TaskStatus's three terminals into a
/// single [done] lane (per-card outcome icon distinguishes done/failed/
/// cancelled). See docs/superpowers/specs/2026-06-15-task-board-design.md §4.1.
enum BoardColumn { pending, claimed, done }

/// Pure mapping between [TaskStatus] and [BoardColumn].
extension BoardColumnMapping on BoardColumn {
  static BoardColumn forStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return BoardColumn.pending;
      case TaskStatus.claimed:
        return BoardColumn.claimed;
      case TaskStatus.done:
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return BoardColumn.done;
    }
  }

  static List<TaskStatus> statusesFor(BoardColumn column) {
    switch (column) {
      case BoardColumn.pending:
        return const [TaskStatus.pending];
      case BoardColumn.claimed:
        return const [TaskStatus.claimed];
      case BoardColumn.done:
        return const [
          TaskStatus.done,
          TaskStatus.failed,
          TaskStatus.cancelled,
        ];
    }
  }
}
