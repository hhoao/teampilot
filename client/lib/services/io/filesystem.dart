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

abstract interface class Filesystem {
  p.Context get pathContext;

  Future<FsStat> stat(String path);
  Future<void> ensureDir(String path);
  Future<void> removeRecursive(String path);
  Future<void> rename(String from, String to);

  Future<String?> readString(String path);
  Future<void> writeString(String path, String content);
  Future<void> atomicWrite(String path, String content);
  Future<List<FsDirEntry>> listDir(String path);

  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  });

  Future<void> copyTree({required String source, required String destination});
}
