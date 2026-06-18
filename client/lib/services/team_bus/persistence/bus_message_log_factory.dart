import '../../storage/app_storage.dart';
import '../../storage/workspace_layout.dart';
import 'bus_message_log.dart';
import 'file_bus_message_log.dart';
import 'in_memory_bus_message_log.dart';

/// 按 session 创建事件日志目录:`{sessionDir}/bus/mail/{role}.jsonl`。
/// `local-` 前缀走内存。路径布局见 [WorkspaceLayout]。
abstract final class BusMessageLogFactory {
  BusMessageLogFactory._();

  static BusMessageLog forSession(String workspaceId, String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryBusMessageLog();
    }
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    return FileBusMessageLog(
      mailRoot: layout.busMailDir(workspaceId, sessionId),
      fs: AppStorage.fs,
    );
  }
}
