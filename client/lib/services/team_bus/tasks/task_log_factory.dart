import '../../storage/app_storage.dart';
import 'file_task_log.dart';
import 'in_memory_task_log.dart';
import 'task_log.dart';

/// 按 session 创建任务日志目录。对齐 [BusMessageLogFactory]：`local-` 前缀走内存，
/// 否则落 `{appProjectsDir}/sessions/bus-tasks/{sessionId}/tasks.jsonl`。
abstract final class TaskLogFactory {
  TaskLogFactory._();

  static TaskLog forSession(String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryTaskLog();
    }
    final root = AppStorage.paths.appProjectsDir;
    final queueRoot = AppStorage.fs.pathContext.join(
      root,
      'sessions',
      'bus-tasks',
      sessionId,
    );
    return FileTaskLog(queueRoot: queueRoot, fs: AppStorage.fs);
  }
}
