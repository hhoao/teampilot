import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';

class InMemoryFilesystem implements Filesystem {
  InMemoryFilesystem({p.Context? pathContext})
    : pathContext = pathContext ?? p.Context(style: p.Style.posix);

  @override
  final p.Context pathContext;

  final Map<String, String> files = {};
  final Map<String, List<int>> byteFiles = {};
  final Set<String> directories = {};
  final Map<String, String> symlinks = {};

  /// Resolve [path] through an ancestor directory symlink, if any.
  String _follow(String path) {
    var current = path;
    while (true) {
      final parent = pathContext.dirname(current);
      if (parent == current || parent.isEmpty) return path;
      final target = symlinks[parent];
      if (target != null) {
        final rel = pathContext.relative(path, from: parent);
        return rel == '.' ? target : pathContext.join(target, rel);
      }
      current = parent;
    }
  }

  @override
  Future<FsStat> stat(String path) async {
    Future<FsStat> direct(String p) async {
      if (byteFiles.containsKey(p)) {
        return FsStat(kind: FsEntityKind.file, size: byteFiles[p]!.length);
      }
      if (files.containsKey(p)) {
        return FsStat(kind: FsEntityKind.file, size: files[p]!.length);
      }
      if (directories.contains(p)) {
        return const FsStat(kind: FsEntityKind.directory);
      }
      if (symlinks.containsKey(p)) {
        return const FsStat(kind: FsEntityKind.symlink);
      }
      return const FsStat(kind: FsEntityKind.notFound);
    }

    final own = await direct(path);
    if (own.exists) return own;
    final followed = _follow(path);
    if (followed != path) return direct(followed);
    return own;
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
    byteFiles.removeWhere(
      (key, _) => key == path || pathContext.isWithin(path, key),
    );
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
    final fromStat = await stat(from);
    if (!fromStat.exists) return;

    await ensureDir(pathContext.dirname(to));

    if (fromStat.isDirectory) {
      directories.add(to);
      directories.remove(from);

      for (final dir in directories.toList()) {
        if (pathContext.isWithin(from, dir) && dir != from) {
          directories.remove(dir);
          directories.add(pathContext.join(to, pathContext.relative(dir, from: from)));
        }
      }
      for (final key in files.keys.toList()) {
        if (pathContext.isWithin(from, key)) {
          files[pathContext.join(to, pathContext.relative(key, from: from))] =
              files.remove(key)!;
        }
      }
      for (final key in byteFiles.keys.toList()) {
        if (pathContext.isWithin(from, key)) {
          byteFiles[pathContext.join(to, pathContext.relative(key, from: from))] =
              byteFiles.remove(key)!;
        }
      }
      for (final key in symlinks.keys.toList()) {
        if (pathContext.isWithin(from, key)) {
          symlinks[pathContext.join(to, pathContext.relative(key, from: from))] =
              symlinks.remove(key)!;
        }
      }
      return;
    }

    final content = files.remove(from);
    if (content != null) {
      files[to] = content;
      return;
    }

    final bytes = byteFiles.remove(from);
    if (bytes != null) {
      byteFiles[to] = bytes;
      return;
    }

    final linkTarget = symlinks.remove(from);
    if (linkTarget != null) {
      symlinks[to] = linkTarget;
    }
  }

  @override
  Future<String?> readString(String path) async {
    final direct = files[path];
    if (direct != null) return direct;
    final followed = _follow(path);
    return followed == path ? null : files[followed];
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final bytes = byteFiles[path];
    if (bytes != null) return bytes;
    final text = files[path];
    if (text != null) return text.codeUnits;
    final followed = _follow(path);
    if (followed == path) return null;
    final followedBytes = byteFiles[followed];
    if (followedBytes != null) return followedBytes;
    final followedText = files[followed];
    return followedText?.codeUnits;
  }

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    byteFiles.remove(path);
    files[path] = content;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    files.remove(path);
    byteFiles[path] = List<int>.from(bytes);
  }

  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final all = await readBytes(path);
    if (all == null) return null;
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (offset >= all.length) return <int>[];
    final end = (offset + length).clamp(0, all.length);
    return all.sublist(offset, end);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final existing = await readBytes(path) ?? <int>[];
    await writeBytes(path, [...existing, ...bytes]);
  }

  @override
  Future<void> atomicWrite(String path, String content) =>
      writeString(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    if (symlinks.containsKey(path)) {
      return listDir(symlinks[path]!);
    }
    final followed = _follow(path);
    final listPath = followed != path ? followed : path;
    final names = <String, bool>{};
    for (final dir in directories) {
      if (pathContext.dirname(dir) == listPath) {
        names[pathContext.basename(dir)] = true;
      }
    }
    for (final file in files.keys) {
      if (pathContext.dirname(file) == listPath) {
        names[pathContext.basename(file)] = false;
      }
    }
    for (final file in byteFiles.keys) {
      if (pathContext.dirname(file) == listPath) {
        names[pathContext.basename(file)] = false;
      }
    }
    for (final link in symlinks.keys) {
      if (pathContext.dirname(link) == listPath) {
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
  Future<String?> readSymlinkTarget(String linkPath) async =>
      symlinks[linkPath];

  @override
  Future<String?> resolveSymlink(String path) async => symlinks[path] ?? path;

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

  @override
  Future<void> copyFile(String source, String destination) async {
    final text = files[source];
    final bytes = byteFiles[source];
    await ensureDir(pathContext.dirname(destination));
    if (text != null) {
      files[destination] = text;
    } else if (bytes != null) {
      byteFiles[destination] = List<int>.from(bytes);
    }
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async {
    final entries = <String, bool>{};
    for (final key in files.keys) {
      if (key == path || pathContext.isWithin(path, key)) {
        entries[pathContext.relative(key, from: path)] = false;
      }
    }
    for (final key in byteFiles.keys) {
      if (key == path || pathContext.isWithin(path, key)) {
        entries[pathContext.relative(key, from: path)] = false;
      }
    }
    for (final key in directories) {
      if (key != path && pathContext.isWithin(path, key)) {
        entries[pathContext.relative(key, from: path)] = true;
      }
    }
    return [
      for (final e in entries.entries)
        FsDirEntry(name: e.key, isDirectory: e.value),
    ];
  }

  static int _tmpDirCounter = 0;

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    final base = parent ?? '/tmp';
    final name =
        '${prefix ?? ''}${DateTime.now().microsecondsSinceEpoch}_${_tmpDirCounter++}';
    final fullPath = pathContext.join(base, name);
    directories.add(fullPath);
    return fullPath;
  }

  @override
  Future<void> appendString(String path, String content) async {
    final existing = files[path];
    files[path] = (existing ?? '') + content;
    byteFiles.remove(path);
  }
}
