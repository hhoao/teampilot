import 'async_keyed_coalescer.dart';

/// Process-wide coalesce for skill/plugin repo disk sync.
class RepoDiskSyncCoalescer {
  RepoDiskSyncCoalescer._();
  static final instance = AsyncKeyedCoalescer();

  static String syncKey(String cacheRoot, String repoKey) =>
      '$cacheRoot|$repoKey';
}
