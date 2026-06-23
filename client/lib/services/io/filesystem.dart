import 'package:path/path.dart' as p;


enum FsEntityKind { file, directory, symlink, notFound }

class FsStat {
  const FsStat({required this.kind, this.size, this.mtime});

  final FsEntityKind kind;
  final int? size;
  final DateTime? mtime;

  bool get exists => kind != FsEntityKind.notFound;
  bool get isDirectory => kind == FsEntityKind.directory;
  bool get isFile => kind == FsEntityKind.file;
  bool get isSymlink => kind == FsEntityKind.symlink;
}

class FsDirEntry {
  const FsDirEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

enum FsChangeType { created, modified, deleted, unknown }

class FsChangeEvent {
  const FsChangeEvent({required this.path, required this.type});

  final String path;
  final FsChangeType type;
}

/// Optional [Filesystem] capability: backends that can push change
/// notifications for a directory subtree implement this.
///
/// Backends without a native watch primitive (e.g. SFTP) deliberately do NOT
/// implement it, so callers must feature-detect (`fs is FsWatcher`) and fall
/// back to manual / activity-driven refresh. Treat emitted events as coarse
/// hints — re-read the affected state rather than trusting the payload exactly.
abstract interface class FsWatcher {
  /// Emits change events for anything under [path], recursively.
  Stream<FsChangeEvent> watchTree(String path);
}

abstract interface class Filesystem {
  p.Context get pathContext;

  Future<FsStat> stat(String path);
  Future<void> ensureDir(String path);
  Future<void> removeRecursive(String path);
  Future<void> rename(String from, String to);

  Future<String?> readString(String path);
  Future<List<int>?> readBytes(String path);
  Future<void> writeString(String path, String content);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> atomicWrite(String path, String content);
  Future<List<FsDirEntry>> listDir(String path);

  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  });

  /// Resolved target path when [linkPath] is a symlink; otherwise `null`.
  Future<String?> readSymlinkTarget(String linkPath);

  /// Canonical absolute path of [path] with all symlinks resolved, or `null`
  /// when it cannot be resolved.
  Future<String?> resolveSymlink(String path);

  Future<void> copyTree({required String source, required String destination});

  Future<void> copyFile(String source, String destination);

  Future<List<FsDirEntry>> listDirRecursive(String path);

  Future<String> createTempDir({String? prefix, String? parent});

  Future<void> appendString(String path, String content);
}
