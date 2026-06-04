import '../../storage/app_storage.dart';
import 'bus_message_log.dart';
import 'file_bus_message_log.dart';
import 'in_memory_bus_message_log.dart';

/// 按 session 创建事件日志目录。
abstract final class BusMessageLogFactory {
  BusMessageLogFactory._();

  static BusMessageLog forSession(String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryBusMessageLog();
    }
    final root = AppStorage.paths.appProjectsDir;
    final mailRoot = AppStorage.fs.pathContext.join(
      root,
      'sessions',
      'bus-mail',
      sessionId,
    );
    return FileBusMessageLog(mailRoot: mailRoot, fs: AppStorage.fs);
  }
}
