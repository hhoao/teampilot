import 'dart:convert';

import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import 'launch_manifest.dart';
import 'launch_manifest_paths.dart';

/// [Filesystem] that records mutations into [manifest] and reads through
/// [readDelegate]. Destructive ops are staged only — [readDelegate] is never
/// mutated (safe when it is the control-plane home catalog during off-home prep).
class ManifestFilesystem implements Filesystem {
  ManifestFilesystem({
    required this.manifest,
    required this.readDelegate,
    p.Context? pathContext,
  }) : pathContext = pathContext ?? readDelegate.pathContext;

  final LaunchManifest manifest;
  final Filesystem readDelegate;

  @override
  final p.Context pathContext;

  final Map<String, String> _overlayFiles = {};
  final Map<String, String> _overlaySymlinks = {};
  final Set<String> _overlayDirs = {};

  String _normalize(String path) => normalizeWorkPath(this, path);

  void _clearOverlayUnder(String path) {
    path = _normalize(path);
    _overlayFiles.removeWhere(
      (key, _) => key == path || pathContext.isWithin(path, key),
    );
    _overlaySymlinks.removeWhere(
      (key, _) => key == path || pathContext.isWithin(path, key),
    );
    _overlayDirs.removeWhere(
      (key) => key == path || pathContext.isWithin(path, key),
    );
  }

  @override
  Future<FsStat> stat(String path) async {
    if (_overlayFiles.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.file);
    }
    if (_overlaySymlinks.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.symlink);
    }
    if (_overlayDirs.contains(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    return readDelegate.stat(path);
  }

  @override
  Future<void> ensureDir(String path) async {
    path = _normalize(path);
    var current = pathContext.rootPrefix(path);
    for (final part in pathContext.split(path)) {
      if (part == current || part.isEmpty) continue;
      current = current.isEmpty ? part : pathContext.join(current, part);
      _overlayDirs.add(current);
      manifest.ensureDir(current);
    }
    _overlayDirs.add(path);
    manifest.ensureDir(path);
  }

  @override
  Future<void> removeRecursive(String path) async {
    _clearOverlayUnder(path);
    manifest.removeRecursive(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    final symlinkTarget = _overlaySymlinks.remove(from);
    if (symlinkTarget != null) {
      _clearOverlayUnder(from);
      await ensureDir(pathContext.dirname(to));
      _overlaySymlinks[to] = symlinkTarget;
      manifest.symlink(linkPath: to, target: symlinkTarget);
      manifest.removeRecursive(from);
      return;
    }
    final content = _overlayFiles.remove(from);
    if (content != null) {
      _clearOverlayUnder(from);
      await ensureDir(pathContext.dirname(to));
      _overlayFiles[to] = content;
      manifest.writeFile(to, content);
      manifest.removeRecursive(from);
      return;
    }

    final stat = await readDelegate.stat(from);
    if (stat.isFile) {
      final bytes = await readDelegate.readBytes(from);
      if (bytes != null) {
        await writeString(to, utf8.decode(bytes, allowMalformed: true));
        manifest.removeRecursive(from);
      }
      return;
    }
    if (stat.isSymlink) {
      final target = await readDelegate.readSymlinkTarget(from);
      if (target != null) {
        await createSymlink(target: target, linkPath: to);
        manifest.removeRecursive(from);
      }
      return;
    }
    if (stat.isDirectory) {
      manifest.rename(from: from, to: to);
      _clearOverlayUnder(from);
    }
  }

  @override
  Future<String?> readString(String path) async =>
      _overlayFiles[path] ?? readDelegate.readString(path);

  @override
  Future<List<int>?> readBytes(String path) async {
    final overlay = _overlayFiles[path];
    if (overlay != null) return utf8.encode(overlay);
    return readDelegate.readBytes(path);
  }

  @override
  Future<void> writeString(String path, String content) async {
    path = _normalize(path);
    await ensureDir(pathContext.dirname(path));
    _overlayFiles[path] = content;
    manifest.writeFile(path, content);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await writeString(path, utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final all = await readBytes(path);
    if (all == null) return null;
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
  Future<void> atomicWrite(String path, String content) async =>
      writeString(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    path = _normalize(path);
    // ensureDir walks parents into _overlayDirs (e.g. $HOME when staging a
    // session tree under it). Do not hide an already-real directory — that
    // breaks Cursor home passthrough listDir($HOME). Only staged dirs that
    // do not exist on the read delegate stay empty.
    if (_overlayDirs.contains(path)) {
      final real = await readDelegate.stat(path);
      if (!real.exists) return const [];
    }
    return readDelegate.listDir(path);
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async =>
      readDelegate.listDirRecursive(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    target = _normalize(target);
    linkPath = _normalize(linkPath);
    await ensureDir(pathContext.dirname(linkPath));
    _overlaySymlinks[linkPath] = target;
    manifest.symlink(linkPath: linkPath, target: target);
    return true;
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async =>
      _overlaySymlinks[linkPath] ?? readDelegate.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) async =>
      _overlaySymlinks[path] ?? readDelegate.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    manifest.copyTree(source: source, destination: destination);
    await ensureDir(pathContext.dirname(destination));
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    manifest.copyFile(source: source, destination: destination);
    await ensureDir(pathContext.dirname(destination));
  }

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    final dir = pathContext.join(
      parent ?? pathContext.join('', 'tmp'),
      '${prefix ?? 'manifest'}_${DateTime.now().microsecondsSinceEpoch}',
    );
    await ensureDir(dir);
    return dir;
  }

  @override
  Future<void> appendString(String path, String content) async {
    final existing = (await readString(path)) ?? '';
    await writeString(path, existing + content);
  }
}
