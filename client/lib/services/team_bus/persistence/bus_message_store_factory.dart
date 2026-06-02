import '../../storage/app_storage.dart';
import 'bus_message_store.dart';
import 'file_bus_message_store.dart';
import 'in_memory_bus_message_store.dart';

/// 按 session 创建冷层存储目录。
abstract final class BusMessageStoreFactory {
  BusMessageStoreFactory._();

  static final memory = InMemoryBusMessageStore();

  static BusMessageStore forSession(String sessionId) {
    if (sessionId.startsWith('local-')) {
      return InMemoryBusMessageStore();
    }
    final root = AppStorage.paths.appProjectsDir;
    final mailRoot = AppStorage.fs.pathContext.join(
      root,
      'sessions',
      'bus-mail',
      sessionId,
    );
    return FileBusMessageStore(mailRoot: mailRoot, fs: AppStorage.fs);
  }
}
