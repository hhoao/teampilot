import 'dart:io';

import 'package:path/path.dart' as p;

import 'filesystem.dart';

class LocalFilesystem implements Filesystem {
  LocalFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.context;

  static int _tmpWriteCounter = 0;

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
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await _deleteIfStillPresent(Directory(path), recursive: true);
      case FileSystemEntityType.link:
        await _deleteIfStillPresent(Link(path));
      case FileSystemEntityType.file:
        await _deleteIfStillPresent(File(path));
      case FileSystemEntityType.notFound:
        break;
      default:
        break;
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
  Future<void> atomicWrite(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    final tmp =
        '$path.tmp.${DateTime.now().microsecondsSinceEpoch}.${_tmpWriteCounter++}';
    await File(tmp).writeAsString(content, flush: true);
    await File(tmp).rename(path);
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
