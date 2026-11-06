import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../remote/runtime_materialization_policy.dart';
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
  RuntimeMaterializationPolicy policy = const RuntimeMaterializationPolicy(),
  bool? serverSideCopyOverride,
}) {
  return _WorkPathProjector(
    manifest: manifest,
    sourceFs: sourceFs,
    workFs: workFs,
    homeRoot: homeRoot,
    workRoot: workRoot,
    policy: policy,
    serverSideCopyOverride: serverSideCopyOverride,
  ).build();
}

/// Stamp written next to a work-machine shared bundle so later launches can
/// keep the session link without re-uploading the tree.
const String sharedBundleStampFileName = '.teampilot-bundle-stamp';

/// Work-plane directory holding content-addressed copies of shared bundles
/// (`<workRoot>/.teampilot-bundles/<stamp>/plugins/…`).
const String bundleGenerationsDirName = '.teampilot-bundles';

/// Work-plane top-level roots whose trees are shared by every session on a
/// machine (`<workRoot>/plugins`, `<workRoot>/skills`). `cli-defaults` and
/// workspace config are already mirrored by `WorkMachineMaterializer`.
const Set<String> _sharedBundleRoots = {'plugins', 'skills'};

final class _WorkPathProjector {
  _WorkPathProjector({
    required this.manifest,
    required this.sourceFs,
    required this.workFs,
    required String homeRoot,
    required String workRoot,
    this.policy = const RuntimeMaterializationPolicy(),
    this.serverSideCopyOverride,
  }) : homeRoot = sourceFs.pathContext.normalize(homeRoot),
       workRoot = workFs.pathContext.normalize(workRoot),
       // When both planes are the same remote filesystem, the bytes are
       // already on the work machine: copying them into the phone (as blobs)
       // and uploading them back is pure overhead.
       serverSideCopy =
           serverSideCopyOverride ??
           (identical(sourceFs, workFs) && workFs.isRemote);

  final LaunchManifest manifest;
  final Filesystem sourceFs;
  final Filesystem workFs;
  final RuntimeMaterializationPolicy policy;
  final bool? serverSideCopyOverride;
  final bool serverSideCopy;
  final String homeRoot;
  final String workRoot;
  final MemoryBlobStore blobs = MemoryBlobStore();
  final List<ApplyOp> _ops = [];
  int _providedLinks = 0;

  /// Shared bundles already emitted (or validated) in this plan, so a tree is
  /// never shipped twice in the same overlay.
  final Set<String> _seededBundles = <String>{};
  final Map<String, String?> _remoteBundleStamps = <String, String?>{};

  Future<ApplyPlanBuild> build() async {
    for (
      var entryIndex = 0;
      entryIndex < manifest.entries.length;
      entryIndex++
    ) {
      final entry = manifest.entries[entryIndex];
      switch (entry) {
        case ManifestEnsureDir(:final path):
          // Host dirs outside the work plane (/var, USERPROFILE, HOME) are
          // already on the machine. 8.3 vs long paths on Windows make the
          // ancestor check miss; skipping is the work-plane no-op.
          final projected = _project(path);
          if (projected != null) {
            _assertPath(projected);
            _ops.add(ApplyEnsureDir(projected));
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
          await _addSymlink(
            linkPath: linkPath,
            target: target,
            entryIndex: entryIndex,
          );
        case ManifestCopyFile(:final source, :final destination, :final private):
          await _addCopyFile(
            source: source,
            destination: destination,
            entryIndex: entryIndex,
            private: private,
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
    required int entryIndex,
  }) async {
    final projectedLink = _projectRequired(linkPath);
    final resolvedTarget = _resolveTarget(target: target, linkPath: linkPath);
    final projectedTarget = _project(resolvedTarget);
    if (projectedTarget == null) {
      await _materializeUnprojectable(
        source: resolvedTarget,
        destination: linkPath,
        entryIndex: entryIndex,
      );
      return;
    }
    // Keep the link when the target is created in this plan (a first-fill
    // hole): seeding it from sourceFs would fight the later writes.
    if (_planCreates(resolvedTarget)) {
      _ops.add(ApplySymlink(linkPath: projectedLink, target: projectedTarget));
      return;
    }
    // Shared bundles (plugins/skills) live once per work machine.
    // Seed a content generation instead of copying the tree into every
    // session's link path; later launches reuse it and only re-link.
    final seededTarget = await _seedSharedBundle(
      source: resolvedTarget,
      candidate: projectedTarget,
      linkPath: projectedLink,
    );
    if (seededTarget != null) {
      _ops.add(ApplySymlink(linkPath: projectedLink, target: seededTarget));
      return;
    }
    if (await _isProvided(resolvedTarget, projectedTarget)) {
      _providedLinks++;
      _ops.add(ApplySymlink(linkPath: projectedLink, target: projectedTarget));
      return;
    }
    // Copy only when sourceFs already has content that remote does not.
    if (!await _sourceHasContent(resolvedTarget)) {
      _ops.add(ApplySymlink(linkPath: projectedLink, target: projectedTarget));
      return;
    }
    await _materializeUnprojectable(
      source: resolvedTarget,
      destination: linkPath,
      entryIndex: entryIndex,
    );
  }

  /// Whether [candidate] sits under a machine-shared bundle root.
  bool _isSharedBundleRoot(String candidate) {
    final ctx = workFs.pathContext;
    final normalized = ctx.normalize(candidate);
    if (normalized == workRoot || !ctx.isWithin(workRoot, normalized)) {
      return false;
    }
    final parts = ctx.split(ctx.relative(normalized, from: workRoot));
    return parts.isNotEmpty && _sharedBundleRoots.contains(parts.first);
  }

  /// Seeds (or reuses) a machine-shared directory bundle on the work plane.
  ///
  /// Returns the path the session link must point at, or null when this is not
  /// a shared bundle (non-bundle path, file target, same-machine flush, or a
  /// nested/self link): those carry per-session mutable state and must keep the
  /// caller's copy path.
  ///
  /// Seeded trees are content-addressed (`<workRoot>/.teampilot-bundles/<stamp>`)
  /// so an update never deletes a tree another session is running from, and a
  /// re-seed never needs a destructive `rm -rf` (which would race concurrent
  /// team launches). Old generations are left in place; they are a few MB and
  /// are shared by every later launch that resolves to the same stamp.
  Future<String?> _seedSharedBundle({
    required String source,
    required String candidate,
    required String linkPath,
  }) async {
    // Same filesystem: the target already is the source, nothing to ship.
    if (identical(sourceFs, workFs)) return null;
    if (candidate == linkPath) return null;
    final ctx = workFs.pathContext;
    if (ctx.isWithin(candidate, linkPath) ||
        ctx.isWithin(linkPath, candidate)) {
      return null;
    }
    if (!_isSharedBundleRoot(candidate)) return null;
    if (!(await sourceFs.stat(source)).isDirectory) return null;

    final relPaths = await _bundleFileRelPaths(source);
    final stamp = await _bundleStamp(source, relPaths);
    final generation = _bundleGenerationDir(candidate, stamp);
    _providedLinks++;
    // The marker member is written last, so a matching stamp also proves the
    // previous extraction finished.
    final remoteStamp = await _remoteBundleStamp(generation);
    if (remoteStamp == stamp) return generation;
    if (!_seededBundles.add(generation)) return generation;

    appLogger.d(
      '[session-launch] bundle-seed dest=$generation source=$candidate '
      'files=${relPaths.length}',
    );
    final entries = <ApplyTreeEntry>[];
    for (final rel in relPaths) {
      final bytes = await sourceFs.readBytes(
        sourceFs.pathContext.join(source, rel),
      );
      if (bytes == null) continue;
      entries.add(ApplyTreeEntry(rel: rel, sha256: await _storeBlob(bytes)));
    }
    if (entries.isEmpty) {
      _ops.add(ApplyEnsureDir(generation));
    } else {
      _ops.add(ApplyTree(dest: generation, entries: entries));
    }
    _ops.add(
      ApplyWriteBlob(
        path: ctx.join(generation, sharedBundleStampFileName),
        sha256: await _storeBlob(utf8.encode(stamp)),
        mode: 0x1a4,
      ),
    );
    return generation;
  }

  /// Content-addressed location for a shared bundle generation.
  String _bundleGenerationDir(String candidate, String stamp) {
    final ctx = workFs.pathContext;
    final rel = ctx.relative(candidate, from: workRoot);
    return ctx.join(
      workRoot,
      bundleGenerationsDirName,
      stamp.substring(0, 16),
      rel,
    );
  }

  Future<String?> _remoteBundleStamp(String generation) async {
    if (_remoteBundleStamps.containsKey(generation)) {
      return _remoteBundleStamps[generation];
    }
    final stamp = await workFs.readString(
      workFs.pathContext.join(generation, sharedBundleStampFileName),
    );
    _remoteBundleStamps[generation] = stamp;
    return stamp;
  }

  /// Files to ship for a shared bundle: directories dropped, VCS/scratch
  /// metadata dropped, and any stale marker from the source ignored.
  Future<List<String>> _bundleFileRelPaths(String source) async {
    final entries = await sourceFs.listDirRecursive(source);
    final rels = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final rel = entry.name;
      if (!policy.includesPath(rel)) continue;
      if (sourceFs.pathContext.basename(rel) == sharedBundleStampFileName) {
        continue;
      }
      rels.add(rel);
    }
    rels.sort();
    return rels;
  }

  Future<String> _bundleStamp(String source, List<String> relPaths) async {
    final buffer = StringBuffer();
    for (final rel in relPaths) {
      final stat = await sourceFs.stat(sourceFs.pathContext.join(source, rel));
      buffer
        ..write(rel)
        ..write('\t')
        ..write(stat.size ?? 0)
        ..write('\t')
        ..write(stat.mtime?.millisecondsSinceEpoch ?? 0)
        ..write('\n');
    }
    return contentSha256Hex(utf8.encode(buffer.toString()));
  }

  Future<bool> _sourceHasContent(String path) async {
    final stat = await sourceFs.lstat(path);
    return stat.isFile || stat.isDirectory || stat.isSymlink;
  }

  Future<void> _materializeUnprojectable({
    required String source,
    required String destination,
    required int entryIndex,
    Set<String>? visited,
  }) async {
    final seen = visited ?? <String>{};
    if (!seen.add(source)) {
      throw StateError('symlink target cycle: $source');
    }
    final stat = await sourceFs.lstat(source);
    if (stat.isFile) {
      appLogger.d(
        '[session-launch] apply-plan materialize file not on work plane '
        'dest=$destination source=$source',
      );
      await _addCopyFile(
        source: source,
        destination: destination,
        entryIndex: entryIndex,
      );
      return;
    }
    if (stat.isDirectory) {
      appLogger.d(
        '[session-launch] apply-plan materialize dir not on work plane '
        'dest=$destination source=$source',
      );
      await _addCopyTree(
        source: source,
        destination: destination,
        entryIndex: entryIndex,
      );
      return;
    }
    if (stat.isSymlink) {
      final nextTarget = await sourceFs.readSymlinkTarget(source);
      if (nextTarget != null) {
        await _materializeUnprojectable(
          source: _resolveTarget(target: nextTarget, linkPath: source),
          destination: destination,
          entryIndex: entryIndex,
          visited: seen,
        );
        return;
      }
    }
    throw StateError('symlink target cannot be projected: $source');
  }

  String _resolveTarget({required String target, required String linkPath}) {
    final context = sourceFs.pathContext;
    final effective = context.isAbsolute(target)
        ? target
        : context.join(context.dirname(linkPath), target);
    return context.normalize(effective);
  }

  Future<void> _addCopyFile({
    required String source,
    required String destination,
    required int entryIndex,
    bool private = false,
  }) async {
    final projectedDest = _projectRequired(destination);
    if (serverSideCopy && !_planCreates(source)) {
      _ops.add(
        ApplyCopyFile(
          source: source,
          destination: projectedDest,
          mode: private ? applyPlanPrivateFileMode : null,
        ),
      );
      return;
    }
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
      ApplyWriteBlob(
        path: projectedDest,
        sha256: await _storeBlob(bytes),
        mode: private ? applyPlanPrivateFileMode : null,
      ),
    );
  }

  Future<void> _addCopyTree({
    required String source,
    required String destination,
    required int entryIndex,
  }) async {
    final projectedDest = _projectRequired(destination);
    final ctx = workFs.pathContext;
    final copiesIntoItself =
        source == projectedDest || ctx.isWithin(source, projectedDest);
    if (serverSideCopy && !_planCreates(source) && !copiesIntoItself) {
      final sourceStat = await sourceFs.stat(source);
      if (!sourceStat.exists) {
        _ops.add(ApplyEnsureDir(projectedDest));
        return;
      }
      _ops.add(ApplyCopyTree(source: source, destination: projectedDest));
      return;
    }
    final candidate = _project(source);
    if (candidate != null &&
        !_hasLaterMutationInside(projectedDest, entryIndex)) {
      if (await _isProvidedDirectory(candidate)) {
        _assertPath(candidate);
        _ops.add(ApplySymlink(linkPath: projectedDest, target: candidate));
        _providedLinks++;
        return;
      }
      // A copyTree of a machine-shared bundle behaves like a symlinked bundle:
      // seed the shared generation and link, so the tree is shipped once per
      // work machine instead of once per session.
      final seeded = await _seedSharedBundle(
        source: source,
        candidate: candidate,
        linkPath: projectedDest,
      );
      if (seeded != null) {
        _ops.add(ApplySymlink(linkPath: projectedDest, target: seeded));
        return;
      }
    }

    final sourceStat = await sourceFs.stat(source);
    if (!sourceStat.isDirectory) {
      // Staging overlays (Windows CLI junctions) record copyTree of a home
      // that exists only in the overlay. Treat a missing disk source as an
      // empty tree — later writeFile ops in the same plan still apply.
      if (!sourceStat.exists) {
        _ops.add(ApplyEnsureDir(projectedDest));
        return;
      }
      throw StateError('copy tree source missing: $source');
    }
    final treeEntries = <ApplyTreeEntry>[];
    var skipped = 0;
    for (final entry in await sourceFs.listDirRecursive(source)) {
      if (entry.isDirectory) continue;
      if (!policy.includesPath(entry.name)) {
        skipped++;
        continue;
      }
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
    if (skipped > 0) {
      appLogger.d(
        '[session-launch] apply-plan skip metadata '
        'dest=$projectedDest files=$skipped',
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

  bool _planCreates(String path) {
    final context = sourceFs.pathContext;
    final normalized = context.normalize(path);
    for (final entry in manifest.entries) {
      for (final created in _createdContentPaths(entry)) {
        final projected = _project(created);
        if (projected == null) continue;
        final n = context.normalize(projected);
        if (n == normalized || context.isWithin(normalized, n)) {
          return true;
        }
        // copyTree/symlink of a parent covers children (plugin root → skills/).
        // EnsureDir of an ancestor does not — mkdir /tp must not keep every ln.
        if (_coversDescendants(entry) && context.isWithin(n, normalized)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _coversDescendants(LaunchManifestEntry entry) {
    return switch (entry) {
      ManifestCopyTree() ||
      ManifestCopyFile() ||
      ManifestSymlink() ||
      ManifestRename() => true,
      ManifestEnsureDir() ||
      ManifestWriteFile() ||
      ManifestRemoveRecursive() => false,
    };
  }

  Iterable<String> _createdContentPaths(LaunchManifestEntry entry) sync* {
    switch (entry) {
      case ManifestEnsureDir(:final path):
        yield path;
      case ManifestWriteFile(:final path):
        yield path;
      case ManifestCopyFile(:final destination) ||
          ManifestCopyTree(:final destination):
        yield destination;
      case ManifestRename(:final to):
        yield to;
      case ManifestSymlink(:final linkPath):
        yield linkPath;
      case ManifestRemoveRecursive():
        break;
    }
  }

  bool _hasLaterMutationInside(String destination, int entryIndex) {
    final context = workFs.pathContext;
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
    final homeCtx = sourceFs.pathContext;
    final asWork = _asWorkPath(path);
    if (asWork != null) {
      return asWork;
    }
    final asHome = homeCtx.normalize(path);
    if (asHome == homeRoot || homeCtx.isWithin(homeRoot, asHome)) {
      return _joinOntoWork(homeCtx.relative(asHome, from: homeRoot));
    }
    // Cursor/Codex Windows junctions relocate HOME to LOCALAPPDATA so the
    // CLI stays under MAX_PATH. Staging writes that physical home; keep it.
    if (isCliRuntimeHomePath(asHome, homeCtx)) {
      return asHome;
    }
    return null;
  }

  String? _asWorkPath(String path) {
    final workCtx = workFs.pathContext;
    bool underWork(String normalized) =>
        normalized == workRoot || workCtx.isWithin(workRoot, normalized);

    final asWork = workCtx.normalize(path);
    if (underWork(asWork)) return asWork;
    // Windows staging can join POSIX work roots with `\`. The work plane is
    // still POSIX, so rewrite separators before membership.
    if (workCtx.style == p.Style.posix && path.contains(r'\')) {
      final asPosix = workCtx.normalize(path.replaceAll(r'\', '/'));
      if (underWork(asPosix)) return asPosix;
    }
    return null;
  }

  String _joinOntoWork(String relative) {
    var out = workRoot;
    for (final part in relative.replaceAll(r'\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      out = workFs.pathContext.join(out, part);
    }
    return workFs.pathContext.normalize(out);
  }

  void _assertPath(String path) {
    if (isCliRuntimeHomePath(path, sourceFs.pathContext)) {
      return;
    }
    assertApplyPath(
      path: path,
      workRoot: workRoot,
      pathContext: workFs.pathContext,
    );
  }
}
