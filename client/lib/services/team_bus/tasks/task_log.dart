import 'team_task.dart';

/// work-queue 的单一事实源：一条 **team 级 append-only 事件日志**。投递（add）与
/// 状态变更（claim / update / reclaim）都是 O(1) 追加，无整文件重写；[load] 回放
/// 重建当前任务表。语义对齐 [BusMessageLog]（每成员信箱），但队列是全队共享、单文件。
abstract interface class TaskLog {
  /// 追加一条入队事件（任务全字段）。
  Future<void> appendAdd(TeamTask task);

  /// 追加一条认领事件。
  Future<void> appendClaim(String taskId, String assignee, int at);

  /// 追加一条状态变更事件（done / failed / cancelled，带可选 result）。
  Future<void> appendUpdate(String taskId, TaskStatus status, String? result, int at);

  /// 追加一条租约回收事件（claimed → pending）。
  Future<void> appendReclaim(String taskId, int at);

  /// 回放全部事件，按 seq 升序返回当前任务表。
  Future<List<TeamTask>> load();
}
