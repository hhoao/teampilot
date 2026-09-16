import 'dart:convert';

import '../io/filesystem.dart';
import 'apply_plan.dart';
import 'blob_store.dart';
import 'launch_manifest.dart';

export 'launch_manifest.dart' show LaunchManifest;

final class ApplyPlanBuild {
  const ApplyPlanBuild({
    required this.plan,
    required this.blobs,
    required this.providedLinks,
  });

  final ApplyPlan plan;
  final MemoryBlobStore blobs;
  final int providedLinks;
}

Future<ApplyPlanBuild> buildApplyPlan({
  required LaunchManifest manifest,
  required Filesystem sourceFs,
  required Filesystem workFs,
  required String homeRoot,
  required String workRoot,
}) {
  return _WorkPathProjector(
    manifest: manifest,
    sourceFs: sourceFs,
    workFs: workFs,
    homeRoot: homeRoot,
    workRoot: workRoot,
  ).build();
}

final class _WorkPathProjector {
  _WorkPathProjector({
    required this.manifest,
    required this.sourceFs,
    required this.workFs,
    required String homeRoot,
    required String workRoot,
  }) : homeRoot = sourceFs.pathContext.normalize(homeRoot),
       workRoot = sourceFs.pathContext.normalize(workRoot);

  final LaunchManifest manifest;
  final Filesystem sourceFs;
  final Filesystem workFs;
  final String homeRoot;
  final String workRoot;
  final MemoryBlobStore blobs = MemoryBlobStore();
  final List<ApplyOp> _ops = [];
  int _providedLinks = 0;

  Future<ApplyPlanBuild> build() async {
    for (
      var entryIndex = 0;
      entryIndex < manifest.entries.length;
      entryIndex++
    ) {
      final entry = manifest.entries[entryIndex];
      switch (entry) {
        case ManifestEnsureDir(:final path):
          final projected = _project(path);
          if (projected != null) {
            _assertPath(projected);
            _ops.add(ApplyEnsureDir(projected));
          } else if (!_isAncestorOfWorkRoot(path)) {
            throw StateError('path cannot be projected: $path');
          }
        case ManifestWriteFile(:final path, :final content):
          await _addWriteFile(path, content);
        case ManifestRemoveRecursive(:final path):
          _ops.add(ApplyRemove(_projectRequired(path)));
        case ManifestRename(:final from, :final to):
          _ops.add(
            ApplyRename(from: _projectRequired(from), to: _projectRequired(to)),
          );
        case ManifestSymlink(:final linkPath, :final target):
          await _addSymlink(linkPath: linkPath, target: target);
        case ManifestCopyFile(:final source, :final destination):
          await _addCopyFile(
            source: source,
            destination: destination,
            entryIndex: entryIndex,
          );
        case ManifestCopyTree(:final source, :final destination):
          await _addCopyTree(
            source: source,
            destination: destination,
            entryIndex: entryIndex,
          );
      }
    }
    return ApplyPlanBuild(
      plan: ApplyPlan(workRoot: workRoot, ops: _ops),
      blobs: blobs,
      providedLinks: _providedLinks,
    );
  }

  Future<void> _addWriteFile(String path, String content) async {
    final projected = _projectRequired(path);
    final bytes = utf8.encode(content);
    if (bytes.length <= applyPlanInlineLimitBytes) {
      _ops.add(ApplyWriteInline(path: projected, content: content));
      return;
    }
    _ops.add(ApplyWriteBlob(path: projected, sha256: await _storeBlob(bytes)));
  }

  Future<void> _addSymlink({
    required String linkPath,
    required String target,
  }) async {
    final projectedLink = _projectRequired(linkPath);
    final projectedTarget = _project(target);
    if (projectedTarget == null) {
      throw StateError('symlink target cannot be projected: $target');
    }
    _assertPath(projectedTarget);
    if (await _isProvided(target, projectedTarget)) {
      _providedLinks++;
    }
    _ops.add(ApplySymlink(linkPath: projectedLink, target: projectedTarget));
  }

  Future<void> _addCopyFile({
    required String source,
    required String destination,
    required int entryIndex,
  }) async {
    final projectedDest = _projectRequired(destination);
    final candidate = _project(source);
    if (candidate != null &&
        !_hasLaterMutationInside(projectedDest, entryIndex) &&
        await _isProvidedFile(source, candidate)) {
      _assertPath(candidate);
      _ops.add(ApplySymlink(linkPath: projectedDest, target: candidate));
      _providedLinks++;
      return;
    }
    final bytes = await sourceFs.readBytes(source);
    if (bytes == null) {
      throw StateError('copy file source missing: $source');
    }
    _ops.add(
      ApplyWriteBlob(path: projectedDest, sha256: await _storeBlob(bytes)),
    );
  }

  Future<void> _addCopyTree({
    required String source,
    required String destination,
    required int entryIndex,
  }) async {
    final projectedDest = _projectRequired(destination);
    final candidate = _project(source);
    if (candidate != null &&
        !_hasLaterMutationInside(projectedDest, entryIndex) &&
        await _isProvidedDirectory(candidate)) {
      _assertPath(candidate);
      _ops.add(ApplySymlink(linkPath: projectedDest, target: candidate));
      _providedLinks++;
      return;
    }

    final sourceStat = await sourceFs.stat(source);
    if (!sourceStat.isDirectory) {
      throw StateError('copy tree source missing: $source');
    }
    final treeEntries = <ApplyTreeEntry>[];
    for (final entry in await sourceFs.listDirRecursive(source)) {
      if (entry.isDirectory) continue;
      final bytes = await sourceFs.readBytes(
        sourceFs.pathContext.join(source, entry.name),
      );
      if (bytes == null) {
        throw StateError('copy tree file missing: ${entry.name}');
      }
      treeEntries.add(
        ApplyTreeEntry(rel: entry.name, sha256: await _storeBlob(bytes)),
      );
    }
    if (treeEntries.isEmpty) {
      _ops.add(ApplyEnsureDir(projectedDest));
    } else {
      _ops.add(ApplyTree(dest: projectedDest, entries: treeEntries));
    }
  }

  Future<bool> _isProvided(String source, String candidate) async {
    final sourceStat = await sourceFs.lstat(source);
    if (sourceStat.isFile) {
      return _isProvidedFile(source, candidate);
    }
    if (sourceStat.isDirectory) {
      return _isProvidedDirectory(candidate);
    }
    if (!sourceStat.isSymlink) return false;
    final sourceTarget = await sourceFs.readSymlinkTarget(source);
    final projectedTarget = sourceTarget == null
        ? null
        : _project(sourceTarget);
    if (projectedTarget == null) return false;
    final candidateStat = await workFs.lstat(candidate);
    return candidateStat.isSymlink &&
        await workFs.readSymlinkTarget(candidate) == projectedTarget;
  }

  Future<bool> _isProvidedFile(String source, String candidate) async {
    if (!(await workFs.lstat(candidate)).isFile) return false;
    final sourceBytes = await sourceFs.readBytes(source);
    final workBytes = await workFs.readBytes(candidate);
    return sourceBytes != null &&
        workBytes != null &&
        contentSha256Hex(sourceBytes) == contentSha256Hex(workBytes);
  }

  Future<bool> _isProvidedDirectory(String candidate) async {
    final candidateStat = await workFs.lstat(candidate);
    if (candidateStat.isDirectory) return true;
    return candidateStat.isSymlink &&
        (await workFs.stat(candidate)).isDirectory;
  }

  bool _hasLaterMutationInside(String destination, int entryIndex) {
    final context = sourceFs.pathContext;
    final normalizedDestination = context.normalize(destination);
    for (var i = entryIndex + 1; i < manifest.entries.length; i++) {
      for (final path in _mutationPaths(manifest.entries[i])) {
        final projected = _project(path);
        if (projected == null) continue;
        final normalizedPath = context.normalize(projected);
        if (normalizedPath == normalizedDestination ||
            context.isWithin(normalizedDestination, normalizedPath)) {
          return true;
        }
      }
    }
    return false;
  }

  Iterable<String> _mutationPaths(LaunchManifestEntry entry) sync* {
    switch (entry) {
      case ManifestWriteFile(:final path):
        yield path;
      case ManifestRemoveRecursive(:final path):
        yield path;
      case ManifestRename(:final from, :final to):
        yield from;
        yield to;
      case ManifestSymlink(:final linkPath):
        yield linkPath;
      case ManifestCopyFile(:final destination) ||
          ManifestCopyTree(:final destination):
        yield destination;
      case ManifestEnsureDir():
        break;
    }
  }

  Future<String> _storeBlob(List<int> bytes) async {
    final sha256 = contentSha256Hex(bytes);
    await blobs.put(sha256, bytes);
    return sha256;
  }

  String _projectRequired(String path) {
    final projected = _project(path);
    if (projected == null) {
      throw StateError('path cannot be projected: $path');
    }
    _assertPath(projected);
    return projected;
  }

  String? _project(String path) {
    final context = sourceFs.pathContext;
    final normalized = context.normalize(path);
    if (normalized == workRoot || context.isWithin(workRoot, normalized)) {
      return normalized;
    }
    if (normalized == homeRoot || context.isWithin(homeRoot, normalized)) {
      return context.join(
        workRoot,
        context.relative(normalized, from: homeRoot),
      );
    }
    return null;
  }

  bool _isAncestorOfWorkRoot(String path) {
    final context = sourceFs.pathContext;
    final normalized = context.normalize(path);
    return context.isWithin(normalized, workRoot);
  }

  void _assertPath(String path) {
    assertApplyPath(
      path: path,
      workRoot: workRoot,
      pathContext: sourceFs.pathContext,
    );
  }
}
