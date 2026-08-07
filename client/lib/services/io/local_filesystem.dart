import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../utils/lock_pool.dart';
import 'filesystem.dart';

class LocalFilesystem implements Filesystem, FsWatcher {
  LocalFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.context;

  static int _tmpWriteCounter = 0;
  static final _atomicWriteLocks = LockPool();

  /// Serializes destructive dir ops with writes into that dir (e.g. concurrent
  /// member connect flushes that `removeRecursive(plugins)` then write a stamp).
  static final _dirMutationLocks = LockPool();

  @override
  final p.Context pathContext;

  @override
  Future<FsStat> stat(String path) async {
    try {
      final entityStat = await FileStat.stat(path);
      return switch (entityStat.type) {
        FileSystemEntityType.directory => FsStat(
          kind: FsEntityKind.directory,
          size: entityStat.size,
          mtime: entityStat.modified,
        ),
        FileSystemEntityType.file => FsStat(
          kind: FsEntityKind.file,
          size: entityStat.size,
          mtime: entityStat.modified,
        ),
        FileSystemEntityType.link => FsStat(
          kind: FsEntityKind.symlink,
          size: entityStat.size,
          mtime: entityStat.modified,
        ),
        _ => const FsStat(kind: FsEntityKind.notFound),
      };
    } on FileSystemException {
      return const FsStat(kind: FsEntityKind.notFound);
    }
  }

  @override
  Future<FsStat> lstat(String path) async {
    // Non-following stat: a symlink-to-directory reports symlink, not the
    // target's directory kind. size/mtime of the link itself are unavailable
    // from dart:io; only kind matters for link-aware callers.
    final kind = FileSystemEntity.typeSync(path, followLinks: false);
    return switch (kind) {
      FileSystemEntityType.directory => const FsStat(
        kind: FsEntityKind.directory,
      ),
      FileSystemEntityType.file => const FsStat(kind: FsEntityKind.file),
      FileSystemEntityType.link => const FsStat(kind: FsEntityKind.symlink),
      _ => const FsStat(kind: FsEntityKind.notFound),
    };
  }

  @override
  Future<void> ensureDir(String path) async {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.directory:
      case FileSystemEntityType.link:
        return;
      case FileSystemEntityType.file:
        throw FileSystemException(
          'ensureDir failed: path is a file',
          path,
          const OSError('Not a directory', 20),
        );
      case FileSystemEntityType.notFound:
        break;
      default:
        break;
    }
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> removeRecursive(String path) async {
    await _dirMutationLocks.synchronized(path, () async {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          await _deleteDirRecursive(path);
        case FileSystemEntityType.link:
          await _deleteIfStillPresent(Link(path));
        case FileSystemEntityType.file:
          await _deleteIfStillPresent(File(path));
        case FileSystemEntityType.notFound:
          break;
        default:
          break;
      }
    });
  }

  /// Recursively deletes a directory, tolerating the `ENOTEMPTY` race where a
  /// concurrent writer (e.g. a second provision of the same member CONFIG_DIR)
  /// adds an entry between Dart's directory walk and its final `rmdir`. Each
  /// retry re-lists the tree, so a child that reappeared is picked up. The dir
  /// still being present after a failed delete (rather than a clean
  /// PathNotFound) is the signal to retry.
  Future<void> _deleteDirRecursive(String path) async {
    const maxAttempts = 8;
    final dir = Directory(path);
    for (var attempt = 1; ; attempt++) {
      try {
        await _deleteIfStillPresent(dir, recursive: true);
        return;
      } on FileSystemException {
        if (!await dir.exists() || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 10 * attempt));
      }
    }
  }

  Future<void> _deleteIfStillPresent(
    FileSystemEntity entity, {
    bool recursive = false,
  }) async {
    try {
      await entity.delete(recursive: recursive);
    } on PathNotFoundException {
      return;
    } on FileSystemException {
      if (!await entity.exists()) return;
      rethrow;
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    await ensureDir(pathContext.dirname(to));
    final type = FileSystemEntity.typeSync(from, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        await File(from).rename(to);
      case FileSystemEntityType.directory:
        try {
          await Directory(from).rename(to);
        } on FileSystemException {
          await removeRecursive(to);
          await Directory(from).rename(to);
        }
      case FileSystemEntityType.link:
        await Link(from).rename(to);
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FileSystemException(
          'rename failed: unsupported entity type',
          from,
        );
      case _:
        throw FileSystemException(
          'rename failed',
          from,
          const OSError('Source path not found', 2),
        );
    }
  }

  @override
  Future<String?> readString(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsString(content);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsBytes(bytes);
  }

  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      return await raf.read(length);
    } on FileSystemException {
      return null;
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    final raf = await File(path).open(mode: FileMode.append);
    try {
      await raf.writeFrom(bytes);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    final parent = pathContext.dirname(path);
    await _dirMutationLocks.synchronized(parent, () async {
      await _atomicWriteLocks.synchronized(path, () async {
        // Retry PathNotFound on all platforms: concurrent member connects may
        // removeRecursive(parent) between ensureDir and rename (team session
        // shares sessionRuntimePluginsDir).
        const maxAttempts = 8;
        for (var attempt = 1; ; attempt++) {
          try {
            await ensureDir(parent);
            final tmp =
                '$path.tmp.${DateTime.now().microsecondsSinceEpoch}.${_tmpWriteCounter++}';
            await File(tmp).writeAsString(content, flush: true);
            try {
              await _renameReplacing(tmp, path);
            } on Object {
              // The rename never made it; drop the temp file so we don't leak it.
              await _deleteIfStillPresent(File(tmp));
              rethrow;
            }
            return;
          } on PathNotFoundException {
            if (attempt >= maxAttempts) rethrow;
            await Future<void>.delayed(Duration(milliseconds: 10 * attempt));
          }
        }
      });
    });
  }

  /// Renames [from] onto [to], overwriting any existing destination.
  ///
  /// POSIX rename is an atomic replace, but on Windows `MoveFile` over an
  /// existing target transiently fails with ACCESS_DENIED (errno 5) while
  /// another rename to the same path is in flight (or AV/indexing briefly
  /// holds it). Retry a handful of times so concurrent atomic writes settle.
  Future<void> _renameReplacing(String from, String to) async {
    const maxAttempts = 20;
    for (var attempt = 1; ; attempt++) {
      try {
        await File(from).rename(to);
        return;
      } on PathAccessException {
        if (!Platform.isWindows || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 5 * attempt));
      }
    }
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final entries = <FsDirEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      entries.add(
        FsDirEntry(
          name: pathContext.basename(entity.path),
          isDirectory: _entryIsDirectory(entity),
        ),
      );
    }
    return entries;
  }

  /// Whether a listed entry resolves to a directory. `Directory.list` with
  /// `followLinks: false` returns symlinks/junctions as [Link]; on Windows
  /// linked dirs (skills, plugins, agents) are junctions, so we resolve the
  /// target type to avoid treating a linked directory as a non-directory.
  bool _entryIsDirectory(FileSystemEntity entity) {
    if (entity is Directory) return true;
    if (entity is Link) {
      return FileSystemEntity.typeSync(entity.path, followLinks: true) ==
          FileSystemEntityType.directory;
    }
    return false;
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await ensureDir(pathContext.dirname(linkPath));
    await removeRecursive(linkPath);
    final normalizedTarget = pathContext.normalize(
      pathContext.absolute(target),
    );
    if (_linkAlreadyPointsTo(target: normalizedTarget, linkPath: linkPath)) {
      return true;
    }

    // Directory junctions avoid Windows "untrusted mount point" (errno 448) when
    // Dart symbolic links are traversed during Directory.create / list.
    if (Platform.isWindows &&
        FileSystemEntity.typeSync(normalizedTarget, followLinks: false) ==
            FileSystemEntityType.directory) {
      if (await _createWindowsJunction(
        linkPath: linkPath,
        target: normalizedTarget,
      )) {
        return true;
      }
    }

    try {
      await Link(linkPath).create(normalizedTarget);
      return true;
    } on FileSystemException catch (e) {
      if (_linkAlreadyPointsTo(target: normalizedTarget, linkPath: linkPath)) {
        return true;
      }
      if (!Platform.isWindows) rethrow;
      if (await _createWindowsJunction(
        linkPath: linkPath,
        target: normalizedTarget,
      )) {
        return true;
      }
      throw FileSystemException('junction failed', linkPath, e.osError);
    }
  }

  Future<bool> _createWindowsJunction({
    required String linkPath,
    required String target,
  }) async {
    final result = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      linkPath,
      target,
    ]);
    if (result.exitCode == 0) return true;
    return _linkAlreadyPointsTo(target: target, linkPath: linkPath);
  }

  bool _linkAlreadyPointsTo({
    required String target,
    required String linkPath,
  }) {
    try {
      final normalizedTarget = pathContext.normalize(target);
      final type = FileSystemEntity.typeSync(linkPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        final existing = Link(linkPath).targetSync();
        return pathContext.normalize(pathContext.absolute(existing)) ==
            normalizedTarget;
      }
      if (Platform.isWindows && type == FileSystemEntityType.directory) {
        final resolved = pathContext.normalize(
          Directory(linkPath).resolveSymbolicLinksSync(),
        );
        return resolved == normalizedTarget;
      }
      return false;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async {
    final link = Link(linkPath);
    if (!await link.exists()) return null;
    try {
      return await link.target();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<String?> resolveSymlink(String path) async {
    try {
      return await File(path).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    final src = Directory(source);
    await removeRecursive(destination);
    await ensureDir(destination);
    if (!await src.exists()) return;
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = pathContext.relative(entity.path, from: src.path);
      final destPath = pathContext.join(destination, rel);
      if (entity is Directory) {
        await ensureDir(destPath);
      } else if (entity is File) {
        await ensureDir(pathContext.dirname(destPath));
        await entity.copy(destPath);
      }
    }
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    await ensureDir(pathContext.dirname(destination));
    await File(source).copy(destination);
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final entries = <FsDirEntry>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      entries.add(
        FsDirEntry(
          name: pathContext.relative(entity.path, from: path),
          isDirectory: _entryIsDirectory(entity),
        ),
      );
    }
    return entries;
  }

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    final base = parent != null ? Directory(parent) : Directory.systemTemp;
    final dir = await base.createTemp(prefix ?? '');
    return dir.path;
  }

  @override
  Future<void> appendString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsString(content, mode: FileMode.append);
  }

  /// Recursive directory watch via `Directory.watch`.
  ///
  /// We intentionally avoid `package:watcher`'s recursive backend on Windows:
  /// it synchronously walks the entire tree with [listSync] on startup (one
  /// [DirectoryTree] node per subdirectory), which freezes the UI on large
  /// workspaces. Coarse OS events are enough here — [WorkspaceFsWatcher]
  /// debounces and callers re-read affected directories anyway.
  @override
  FsTreeWatch watchTree(String path) {
    final controller = StreamController<FsChangeEvent>();
    StreamSubscription<FileSystemEvent>? subscription;

    if (!FileSystemEntity.isWatchSupported) {
      return FsTreeWatch(
        events: const Stream<FsChangeEvent>.empty(),
        close: () async {
          if (!controller.isClosed) {
            await controller.close();
          }
        },
      );
    }

    subscription = Directory(path).watch(recursive: true).listen(
      (event) {
        if (controller.isClosed) return;
        controller.add(
          FsChangeEvent(path: event.path, type: _mapFsChangeType(event)),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
      cancelOnError: false,
    );

    return FsTreeWatch(
      events: controller.stream,
      close: () async {
        await subscription?.cancel();
        subscription = null;
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
  }

  static FsChangeType _mapFsChangeType(FileSystemEvent event) {
    return switch (event.type) {
      FileSystemEvent.create => FsChangeType.created,
      FileSystemEvent.modify => FsChangeType.modified,
      FileSystemEvent.delete => FsChangeType.deleted,
      _ => FsChangeType.unknown,
    };
  }
}
