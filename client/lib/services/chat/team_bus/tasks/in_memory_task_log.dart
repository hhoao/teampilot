import 'task_log.dart';
import 'team_task.dart';

/// 测试 / 无磁盘时的内存任务日志。直接维护任务表，回放即快照。
class InMemoryTaskLog implements TaskLog {
  final Map<String, TeamTask> _tasks = {};

  @override
  Future<void> appendAdd(TeamTask task) async {
    _tasks[task.id] = task;
  }

  @override
  Future<void> appendClaim(String taskId, String assignee, int at) async {
    final t = _tasks[taskId];
    if (t == null) return;
    _tasks[taskId] = t.copyWith(
      status: TaskStatus.claimed,
      assignee: assignee,
      claimedAt: at,
    );
  }

  @override
  Future<void> appendUpdate(
    String taskId,
    TaskStatus status,
    String? result,
    int at,
  ) async {
    final t = _tasks[taskId];
    if (t == null) return;
    _tasks[taskId] = t.copyWith(status: status, result: result, finishedAt: at);
  }

  @override
  Future<void> appendReclaim(String taskId, int at) async {
    final t = _tasks[taskId];
    if (t == null) return;
    _tasks[taskId] = t.copyWith(status: TaskStatus.pending);
  }

  @override
  Future<void> appendEscalate(String taskId, RoutingStage stage, int at) async {
    final t = _tasks[taskId];
    if (t == null) return;
    _tasks[taskId] = t.copyWith(
      routing: t.routing.copyWith(stage: stage, escalatedAt: at),
    );
  }

  @override
  Future<List<TeamTask>> load() async {
    return _tasks.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }
}
