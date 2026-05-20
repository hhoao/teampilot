import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';

class InMemoryFilesystem implements Filesystem {
  InMemoryFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.Context(style: p.Style.posix);

  @override
  final p.Context pathContext;

  final Map<String, String> files = {};
  final Set<String> directories = {};
  final Map<String, String> symlinks = {};

  @override
  Future<FsStat> stat(String path) async {
    if (files.containsKey(path)) return const FsStat(kind: FsEntityKind.file);
    if (directories.contains(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    if (symlinks.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.symlink);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<void> ensureDir(String path) async {
    var current = pathContext.rootPrefix(path);
    for (final part in pathContext.split(path)) {
      if (part == current || part.isEmpty) continue;
      current = current.isEmpty ? part : pathContext.join(current, part);
      directories.add(current);
    }
    directories.add(path);
  }

  @override
  Future<void> removeRecursive(String path) async {
    files.removeWhere(
      (key, _) => key == path || pathContext.isWithin(path, key),
    );
    directories.removeWhere(
      (key) => key == path || pathContext.isWithin(path, key),
    );
    symlinks.removeWhere(
      (key, _) => key == path || pathContext.isWithin(path, key),
    );
  }

  @override
  Future<void> rename(String from, String to) async {
    final content = files.remove(from);
    if (content != null) {
      await ensureDir(pathContext.dirname(to));
      files[to] = content;
    }
  }

  @override
  Future<String?> readString(String path) async => files[path];

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    files[path] = content;
  }

  @override
  Future<void> atomicWrite(String path, String content) =>
      writeString(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    final names = <String, bool>{};
    for (final dir in directories) {
      if (pathContext.dirname(dir) == path) {
        names[pathContext.basename(dir)] = true;
      }
    }
    for (final file in files.keys) {
      if (pathContext.dirname(file) == path) {
        names[pathContext.basename(file)] = false;
      }
    }
    for (final link in symlinks.keys) {
      if (pathContext.dirname(link) == path) {
        names[pathContext.basename(link)] = false;
      }
    }
    return [
      for (final entry in names.entries)
        FsDirEntry(name: entry.key, isDirectory: entry.value),
    ];
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await ensureDir(pathContext.dirname(linkPath));
    symlinks[linkPath] = target;
    return true;
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await ensureDir(destination);
    for (final entry in files.entries.toList()) {
      if (pathContext.isWithin(source, entry.key)) {
        final rel = pathContext.relative(entry.key, from: source);
        files[pathContext.join(destination, rel)] = entry.value;
      }
    }
  }
}
