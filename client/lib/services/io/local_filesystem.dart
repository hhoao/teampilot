import 'dart:io';

import 'package:path/path.dart' as p;

import 'filesystem.dart';

class LocalFilesystem implements Filesystem {
  LocalFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.context;

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
      await link.delete();
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    await ensureDir(pathContext.dirname(to));
    await removeRecursive(to);
    await File(from).rename(to);
  }

  @override
  Future<String?> readString(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    await File(path).writeAsString(content);
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await File(tmp).writeAsString(content);
    await removeRecursive(path);
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
