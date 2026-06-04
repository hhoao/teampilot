import '../../storage/app_storage.dart';
import '../../storage/session_storage_layout.dart';
import 'file_task_log.dart';
import 'in_memory_task_log.dart';
import 'task_log.dart';

/// 按 session 创建任务日志目录:`{sessionDir}/bus-tasks/tasks.jsonl`。
/// 对齐 [BusMessageLogFactory]:`local-` 前缀走内存。布局见 [SessionStorageLayout]。
abstract final class TaskLogFactory {
  TaskLogFactory._();

  static TaskLog forSession(String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryTaskLog();
    }
    final layout = SessionStorageLayout.forProjectsDir(
      AppStorage.paths.appProjectsDir,
      AppStorage.fs.pathContext,
    );
    return FileTaskLog(
      queueRoot: layout.busTasksDir(sessionId),
      fs: AppStorage.fs,
    );
  }
}
