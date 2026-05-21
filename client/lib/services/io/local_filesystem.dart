import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'filesystem.dart';

class _AsyncLock {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() fn) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    return previous.then((_) => fn()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }
}

class LocalFilesystem implements Filesystem {
  LocalFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.context;

  static int _tmpWriteCounter = 0;
  static final Map<String, _AsyncLock> _atomicWriteLocks = {};

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
  Future<void> ensureDir(String path) {
    return Directory(path).create(recursive: true);
  }

  @override
  Future<void> removeRecursive(String path) async {
    final link = Link(path);
    if (await link.exists()) {
      await _deleteIfStillPresent(link);
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await _deleteIfStillPresent(dir, recursive: true);
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await _deleteIfStillPresent(file);
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
    await removeRecursive(to);
    final dir = Directory(from);
    if (await dir.exists()) {
      await dir.rename(to);
      return;
    }
    final file = File(from);
    if (await file.exists()) {
      await file.rename(to);
      return;
    }
    throw FileSystemException('rename failed', from, const OSError('Source path not found', 2));
  }

  @override
  Future<String?> readString(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsString(content);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    final lock = _atomicWriteLocks.putIfAbsent(
      pathContext.normalize(path),
      () => _AsyncLock(),
    );
    await lock.synchronized(() async {
      await ensureDir(pathContext.dirname(path));
      final tmp =
          '$path.tmp.${DateTime.now().microsecondsSinceEpoch}.${_tmpWriteCounter++}';
      await File(tmp).writeAsString(content);
      await _commitAtomicWrite(path, tmp);
    });
  }

  Future<void> _commitAtomicWrite(String path, String tmp) async {
    const maxAttempts = 6;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await File(tmp).rename(path);
        return;
      } on FileSystemException {
        await _deleteFileIfPresent(path);
        try {
          await File(tmp).rename(path);
          return;
        } on FileSystemException {
          if (attempt == maxAttempts - 1) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 15 * (attempt + 1)),
          );
        }
      }
    }
  }

  Future<void> _deleteFileIfPresent(String path) async {
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final target = File(path);
        if (!await target.exists()) return;
        await target.delete();
        return;
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        if (code == 2) return;
        if (_isTransientDeleteError(code) && attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 15 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
  }

  bool _isTransientDeleteError(int? code) {
    if (code == null) return false;
    // Windows: ERROR_ACCESS_DENIED (5), ERROR_SHARING_VIOLATION (32).
    if (Platform.isWindows) return code == 5 || code == 32;
    return false;
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
          isDirectory: entity is Directory,
        ),
      );
    }
    return entries;
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await ensureDir(pathContext.dirname(linkPath));
    await removeRecursive(linkPath);
    try {
      await Link(linkPath).create(target);
      return true;
    } on FileSystemException catch (e) {
      if (!Platform.isWindows) rethrow;
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        linkPath,
        target,
      ]);
      if (result.exitCode == 0) return true;
      throw FileSystemException('junction failed', linkPath, e.osError);
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
}
