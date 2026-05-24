import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../remote_file_store.dart';
import 'filesystem.dart';

class SftpFilesystem implements Filesystem {
  SftpFilesystem(this.store);

  final RemoteFileStore store;

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  @override
  Future<FsStat> stat(String path) async {
    if (path.trim().isEmpty) return const FsStat(kind: FsEntityKind.notFound);
    try {
      final kind = await store.statKind(path);
      return FsStat(kind: kind);
    } on Object {
      return const FsStat(kind: FsEntityKind.notFound);
    }
  }

  @override
  Future<void> ensureDir(String path) => store.ensureDirectory(path);

  @override
  Future<void> removeRecursive(String path) => store.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => store.movePath(from, to);

  @override
  Future<String?> readString(String path) => store.readFile(path);

  @override
  Future<List<int>?> readBytes(String path) => store.readFileBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      store.writeFile(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      store.writeBytes(path, bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  @override
  Future<void> atomicWrite(String path, String content) async {
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await store.writeFile(tmp, content);
    try {
      await store.movePath(tmp, path);
    } on Exception {
      try {
        await store.removeRecursive(tmp);
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    try {
      final entries = await store.listDirectoryEntries(path);
      return [
        for (final entry in entries)
          FsDirEntry(name: entry.name, isDirectory: entry.isDirectory),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await store.createSymlink(target: target, linkPath: linkPath);
    return true;
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await store.removeRecursive(destination);
    await store.ensureDirectory(destination);
    await store.copyTree(source: source, destination: destination);
  }
}
