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
    final parent = pathContext.dirname(path);
    final name = pathContext.basename(path);
    try {
      final siblings = await store.listDirectoryEntries(parent);
      for (final entry in siblings) {
        if (entry.name != name) continue;
        return FsStat(
          kind: entry.isDirectory ? FsEntityKind.directory : FsEntityKind.file,
        );
      }
    } on Object {
      // Fall back to a direct stat probe below.
    }
    return await store.fileExists(path)
        ? const FsStat(kind: FsEntityKind.file)
        : const FsStat(kind: FsEntityKind.notFound);
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
  Future<void> writeString(String path, String content) =>
      store.writeFile(path, content);

  @override
  Future<void> atomicWrite(String path, String content) async {
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await store.writeFile(tmp, content);
    try {
      await store.movePath(tmp, path);
    } on Object {
      await store.writeFile(path, content);
      await store.removeRecursive(tmp);
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
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await store.ensureDirectory(pathContext.dirname(destination));
    await store.removeRecursive(destination);
    await store.ensureDirectory(destination);
    await store.copyTree(source: source, destination: destination);
  }
}
