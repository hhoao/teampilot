import 'dart:io';

import 'package:path/path.dart' as p;

import 'cli_data_layout.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

/// Checks whether the CLI has persisted session state for an [AppSession]
/// across app + team + member tool roots.
class RemoteCliSessionChecker {
  const RemoteCliSessionChecker(this._storageRoots);

  final FlashskyaiStorageRoots _storageRoots;

  Future<bool> exists({
    required String sessionId,
    required String teamId,
    required String primaryPath,
  }) async {
    final id = sessionId.trim();
    if (id.isEmpty) return false;

    final snap = await _storageRoots.resolve();
    final roots = snap.layout.transcriptSearchRoots(
      teamId: teamId,
      runtimeSessionId: id,
    );
    final bucket = CliDataLayout.projectBucketForPrimaryPath(primaryPath);

    if (snap.storageIsRemote && snap.remoteFileStore != null) {
      return _existsRemote(
        store: snap.remoteFileStore!,
        toolRoots: roots,
        sessionId: id,
        bucket: bucket,
      );
    }
    return _existsLocal(toolRoots: roots, sessionId: id, bucket: bucket);
  }

  static bool _existsLocal({
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) {
    for (final root in toolRoots) {
      if (File(p.join(root, 'sessions', '$sessionId.json')).existsSync()) {
        return true;
      }
      final projectsDir = p.join(root, 'projects');
      if (bucket.isNotEmpty) {
        final bucketDir = p.join(projectsDir, bucket);
        if (File(p.join(bucketDir, '$sessionId.jsonl')).existsSync()) {
          return true;
        }
        if (Directory(p.join(bucketDir, sessionId)).existsSync()) return true;
      }
      if (_scanProjectsLocal(projectsDir, sessionId)) return true;
    }
    return false;
  }

  static bool _scanProjectsLocal(String projectsDir, String sessionId) {
    final root = Directory(projectsDir);
    if (!root.existsSync()) return false;
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final bucketPath = entity.path;
        if (File(p.join(bucketPath, '$sessionId.jsonl')).existsSync()) {
          return true;
        }
        if (Directory(p.join(bucketPath, sessionId)).existsSync()) return true;
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<bool> _existsRemote({
    required RemoteFileStore store,
    required Iterable<String> toolRoots,
    required String sessionId,
    required String bucket,
  }) async {
    final posix = p.Context(style: p.Style.posix);
    for (final root in toolRoots) {
      if (await store.fileExists(
        posix.join(root, 'sessions', '$sessionId.json'),
      )) {
        return true;
      }
      final projectsDir = posix.join(root, 'projects');
      if (bucket.isNotEmpty) {
        final bucketDir = posix.join(projectsDir, bucket);
        if (await store.fileExists(
          posix.join(bucketDir, '$sessionId.jsonl'),
        )) {
          return true;
        }
        try {
          final entries = await store.listDirectoryEntries(bucketDir);
          if (entries.any((e) => e.isDirectory && e.name == sessionId)) {
            return true;
          }
        } on Object {
          // fall through to scan
        }
      }
      if (await _scanProjectsRemote(store, projectsDir, sessionId)) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _scanProjectsRemote(
    RemoteFileStore store,
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
          posix.join(bucketPath, '$sessionId.jsonl'),
        )) {
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
