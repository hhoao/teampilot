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

/// A cancellable recursive tree watch started by [FsWatcher.watchTree].
///
/// Callers must [close] the watch when done so the native subscription is
/// cancelled before a replacement watch is started.
class FsTreeWatch {
  const FsTreeWatch({required this.events, required Future<void> Function() close})
    : _close = close;

  final Stream<FsChangeEvent> events;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

/// Optional [Filesystem] capability: backends that can push change
/// notifications for a directory subtree implement this.
///
/// Backends without a native watch primitive (e.g. SFTP) deliberately do NOT
/// implement it, so callers must feature-detect (`fs is FsWatcher`) and fall
/// back to manual / activity-driven refresh. Treat emitted events as coarse
/// hints — re-read the affected state rather than trusting the payload exactly.
abstract interface class FsWatcher {
  /// Watches anything under [path], recursively.
  ///
  /// The returned [FsTreeWatch] must be [FsTreeWatch.close]d when the watch is
  /// no longer needed.
  FsTreeWatch watchTree(String path);
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

  /// Up to [length] bytes from [offset]. Null if missing. Shorter at EOF.
  Future<List<int>?> readBytesRange(String path, int offset, int length);

  /// Create if missing; append [bytes] at end.
  Future<void> appendBytes(String path, List<int> bytes);

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

/// Link-aware stat: the returned kind reflects the path itself, not its
/// symlink target.
///
/// [Filesystem.stat] follows symlinks on real backends (dart:io's `FileStat`
/// follows), so a symlink-to-directory reports `kind: directory` and callers
/// cannot tell a link apart from a real directory. [lstat] reports
/// `kind: symlink` instead. Backends may override with a native no-follow stat;
/// this default derives the kind from [Filesystem.readSymlinkTarget] and falls
/// back to [Filesystem.stat].
extension FilesystemLstat on Filesystem {
  Future<FsStat> lstat(String path) async {
    if (await readSymlinkTarget(path) != null) {
      return const FsStat(kind: FsEntityKind.symlink);
    }
    return stat(path);
  }
}
