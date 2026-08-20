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

  /// When [path] is under an overlay symlink, return the resolved path on
  /// [readDelegate]. When [path] is the symlink itself, return `null` so
  /// callers can treat it as a link node.
  String? _resolveViaOverlaySymlink(String path) {
    path = _normalize(path);
    if (_overlaySymlinks.containsKey(path)) return null;
    var current = path;
    while (true) {
      final parent = pathContext.dirname(current);
      if (parent == current || parent.isEmpty) return null;
      final target = _overlaySymlinks[parent];
      if (target != null) {
        final rel = pathContext.relative(path, from: parent);
        return rel == '.' ? target : pathContext.join(target, rel);
      }
      current = parent;
    }
  }

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
    path = _normalize(path);
    if (_overlayFiles.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.file);
    }
    if (_overlaySymlinks.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.symlink);
    }
    if (_overlayDirs.contains(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    final resolved = _resolveViaOverlaySymlink(path);
    if (resolved != null) {
      // The overlay symlink target may itself be a path staged during this
      // pass (e.g. flavor projection seeded into an installed bundle that the
      // session plugin pool symlinks to). Check the overlay maps for the
      // resolved target before falling through to the read delegate.
      if (_overlayFiles.containsKey(resolved)) {
        return const FsStat(kind: FsEntityKind.file);
      }
      if (_overlaySymlinks.containsKey(resolved)) {
        return const FsStat(kind: FsEntityKind.symlink);
      }
      if (_overlayDirs.contains(resolved)) {
        return const FsStat(kind: FsEntityKind.directory);
      }
      return readDelegate.stat(resolved);
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
  Future<String?> readString(String path) async {
    path = _normalize(path);
    final overlay = _overlayFiles[path];
    if (overlay != null) return overlay;
    final resolved = _resolveViaOverlaySymlink(path);
    if (resolved != null) {
      final resolvedOverlay = _overlayFiles[resolved];
      if (resolvedOverlay != null) return resolvedOverlay;
      return readDelegate.readString(resolved);
    }
    return readDelegate.readString(path);
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    path = _normalize(path);
    final overlay = _overlayFiles[path];
    if (overlay != null) return utf8.encode(overlay);
    final resolved = _resolveViaOverlaySymlink(path);
    if (resolved != null) {
      final resolvedOverlay = _overlayFiles[resolved];
      if (resolvedOverlay != null) return utf8.encode(resolvedOverlay);
      return readDelegate.readBytes(resolved);
    }
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

  /// Overlay-only write: seeds `_overlayFiles` so a later read in the same
  /// staging pass sees the content, but records **no** manifest entry.
  ///
  /// Used by `copyTree` to mirror a copied tree into the overlay. Recording
  /// per-file `ManifestWriteFile` entries here would re-write every copied
  /// file with the default mode at flush, stripping the source's executable
  /// bit (e.g. superpowers `hooks/run-hook.cmd`); the `ManifestCopyTree`
  /// entry already applies the real copy (mode-preserving) at flush.
  Future<void> _writeOverlayOnly(String path, List<int> bytes) async {
    path = _normalize(path);
    await ensureDir(pathContext.dirname(path));
    _overlayFiles[path] = utf8.decode(bytes, allowMalformed: true);
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
    final symlinkTarget = _overlaySymlinks[path];
    if (symlinkTarget != null) {
      return listDir(symlinkTarget);
    }
    final resolved = _resolveViaOverlaySymlink(path);
    if (resolved != null) {
      return readDelegate.listDir(resolved);
    }

    final names = <String>{};
    final entries = <FsDirEntry>[];
    // Base listing from the read delegate when the dir is already real there.
    // ensureDir walks parents into _overlayDirs (e.g. $HOME when staging a
    // session tree under it); a real home must still be listed (Cursor
    // passthrough listDir($HOME)).
    final realStat = await readDelegate.stat(path);
    if (realStat.exists && realStat.isDirectory) {
      for (final entry in await readDelegate.listDir(path)) {
        names.add(entry.name);
        entries.add(entry);
      }
    }
    // Surface entries staged during this pass so writers can read back what
    // they wrote (e.g. the plugin writer scans the pool it just materialized).
    final prefix = '$path${pathContext.separator}';
    for (final file in _overlayFiles.keys) {
      final rel = _directChild(prefix, file);
      if (rel != null && names.add(rel)) {
        entries.add(FsDirEntry(name: rel, isDirectory: false));
      }
    }
    for (final dir in _overlayDirs) {
      final rel = _directChild(prefix, dir);
      if (rel != null && names.add(rel)) {
        entries.add(FsDirEntry(name: rel, isDirectory: true));
      }
    }
    for (final link in _overlaySymlinks.keys) {
      final rel = _directChild(prefix, link);
      if (rel != null && names.add(rel)) {
        entries.add(FsDirEntry(name: rel, isDirectory: false));
      }
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  /// Child name if [path] sits directly under [prefix], else `null`.
  String? _directChild(String prefix, String path) {
    if (!path.startsWith(prefix) || path.length <= prefix.length) return null;
    final rel = path.substring(prefix.length);
    return rel.contains(pathContext.separator) ? null : rel;
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
    source = _normalize(source);
    destination = _normalize(destination);
    final sourceStat = await stat(source);
    if (sourceStat.isSymlink) {
      final target = await readSymlinkTarget(source);
      if (target != null) {
        await createSymlink(target: target, linkPath: destination);
      }
      return;
    }
    manifest.copyTree(source: source, destination: destination);
    await ensureDir(pathContext.dirname(destination));
    // Populate the overlay too, so a later read in the same staging pass sees
    // the copied tree (e.g. the plugin writer scans the pool it just
    // materialized). The manifest entry still applies the real copy at flush.
    await _copyTreeIntoOverlay(source, destination);
  }

  Future<void> _copyTreeIntoOverlay(String source, String destination) async {
    // Read through `this` (overlay-first): the source may itself have been
    // staged earlier in this pass (e.g. a flavor projection copying from a
    // just-copied bundle), not present on the read delegate.
    final sourceStat = await stat(source);
    if (sourceStat.isFile) {
      final bytes = await readBytes(source);
      // Overlay-only: no manifest entry (see [_writeOverlayOnly]).
      if (bytes != null) await _writeOverlayOnly(destination, bytes);
      return;
    }
    if (sourceStat.isSymlink) {
      final target = await readSymlinkTarget(source);
      if (target != null) {
        await createSymlink(target: target, linkPath: destination);
      }
      return;
    }
    if (!sourceStat.isDirectory) return;
    await ensureDir(destination);
    for (final entry in await listDir(source)) {
      await _copyTreeIntoOverlay(
        pathContext.join(source, entry.name),
        pathContext.join(destination, entry.name),
      );
    }
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
