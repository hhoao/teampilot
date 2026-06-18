import '../../storage/app_storage.dart';
import '../../storage/workspace_layout.dart';
import 'file_task_log.dart';
import 'in_memory_task_log.dart';
import 'task_log.dart';

/// 按 session 创建任务日志目录:`{sessionDir}/bus/tasks/tasks.jsonl`。
/// 对齐 [BusMessageLogFactory]:`local-` 前缀走内存。布局见 [WorkspaceLayout]。
abstract final class TaskLogFactory {
  TaskLogFactory._();

  static TaskLog forSession(String workspaceId, String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryTaskLog();
    }
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    return FileTaskLog(
      queueRoot: layout.busTasksDir(workspaceId, sessionId),
      fs: AppStorage.fs,
    );
  }
}
