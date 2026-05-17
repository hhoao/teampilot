import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';

/// Checks whether the CLI has persisted session state on the active host.
class RemoteCliSessionChecker {
  const RemoteCliSessionChecker(this._storageRoots);

  final FlashskyaiStorageRoots _storageRoots;

  Future<bool> exists(String sessionId, String primaryPath) async {
    final snap = await _storageRoots.resolve();
    if (!snap.storageIsRemote || snap.remoteFileStore == null) {
      return AppStorage.cliSessionDescriptorExists(sessionId, primaryPath);
    }

    final id = sessionId.trim();
    if (id.isEmpty) return false;

    final store = snap.remoteFileStore!;
    final dataRoot = snap.remoteCliDataDir!;
    final posix = p.Context(style: p.Style.posix);

    if (await store.fileExists(posix.join(dataRoot, 'sessions', '$id.json'))) {
      return true;
    }

    final slug = AppStorage.cliProjectBucketForPrimaryPath(primaryPath);
    if (slug.isNotEmpty) {
      final bucket = posix.join(dataRoot, 'projects', slug);
      if (await store.fileExists(posix.join(bucket, '$id.jsonl'))) {
        return true;
      }
      try {
        final entries = await store.listDirectoryEntries(bucket);
        if (entries.any((e) => e.isDirectory && e.name == id)) {
          return true;
        }
      } on Object {
        // fall through to scan
      }
    }

    return _scanProjects(store, posix.join(dataRoot, 'projects'), id);
  }

  Future<bool> _scanProjects(
    dynamic store,
    String projectsDir,
    String sessionId,
  ) async {
    final posix = p.Context(style: p.Style.posix);
    try {
      final buckets = await store.listDirectoryEntries(projectsDir);
      for (final bucket in buckets) {
        if (!bucket.isDirectory) continue;
        final bucketPath = posix.join(projectsDir, bucket.name);
        if (await store.fileExists(
            posix.join(bucketPath, '$sessionId.jsonl'))) {
          return true;
        }
        try {
          final inner = await store.listDirectoryEntries(bucketPath);
          if (inner.any((e) => e.isDirectory && e.name == sessionId)) {
            return true;
          }
        } on Object {
          continue;
        }
      }
    } on Object {
      return false;
    }
    return false;
  }
}
