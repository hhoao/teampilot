import 'dart:convert';

import '../../io/filesystem.dart';
import 'artifact_exceptions.dart';
import 'artifact_handle.dart';
import 'artifact_partial_meta.dart';
import 'artifact_registry.dart';

/// Result of a successful `fetch_artifact`.
class ArtifactFetchResult {
  const ArtifactFetchResult({
    required this.name,
    required this.finalPath,
    required this.sizeBytes,
    required this.publisherMemberId,
  });

  final String name;
  final String finalPath;
  final int sizeBytes;
  final String publisherMemberId;
}

/// Moves single-file artifacts between members that live on different machines
/// (see remote-execution-architecture §4.2). The bus records only a handle; the
/// **local App** is the one process that can reach both filesystems, so it copies
/// from the publisher's target fs into the fetcher's inbox via fixed-size chunks
/// (`readBytesRange` → `appendBytes`), with optional resume via
/// `{dest}.tp-partial` / `{dest}.tp-partial.meta.json` sidecars. Same-machine
/// fetches use [Filesystem.copyFile] and skip the chunk loop.
///
/// All side-effecting dependencies are injected so this is unit-tested with fake
/// filesystems and no real SSH:
/// - [resolveFs] — target id → its [Filesystem] (wraps `RuntimeContextRegistry`).
/// - [targetForMember] — member id → the RuntimeTarget id it runs on.
/// - [inboxDirFor] — member id → its session inbox dir (the only place a fetch
///   may write; enforced by a path-escape guard).
class ArtifactTransferService {
  ArtifactTransferService({
    required this.registry,
    required Future<Filesystem> Function(String targetId) resolveFs,
    required String Function(String memberId) targetForMember,
    required String Function(String memberId) inboxDirFor,
    this.chunkSize = defaultChunkSize,
    int Function()? nowMs,
  }) : _resolveFs = resolveFs,
       _targetForMember = targetForMember,
       _inboxDirFor = inboxDirFor,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const defaultChunkSize = 4 * 1024 * 1024;

  static String partialPath(String dest) => '$dest.tp-partial';

  static String partialMetaPath(String dest) => '$dest.tp-partial.meta.json';

  final ArtifactRegistry registry;
  final int chunkSize;
  final Future<Filesystem> Function(String targetId) _resolveFs;
  final String Function(String memberId) _targetForMember;
  final String Function(String memberId) _inboxDirFor;
  final int Function() _nowMs;

  /// Register a handle to [path] on [publisherMemberId]'s own machine. Validates
  /// the source is a regular file; never moves bytes. Throws an
  /// [ArtifactException] on rejection.
  Future<ArtifactHandle> publish({
    required String publisherMemberId,
    required String path,
    required String name,
    ArtifactKind kind = ArtifactKind.file,
    bool overwrite = false,
  }) async {
    final targetId = _targetForMember(publisherMemberId);
    final fs = await _resolveFs(targetId);
    final normalized = fs.pathContext.normalize(path.trim());
    final stat = await fs.stat(normalized);
    if (!stat.exists || !stat.isFile) {
      throw ArtifactSourceNotFileException(normalized);
    }
    final size = stat.size ?? -1;
    final handle = ArtifactHandle(
      name: name.trim(),
      publisherMemberId: publisherMemberId,
      targetId: targetId,
      absolutePath: normalized,
      sizeBytes: size,
      kind: kind,
      publishedAtMs: _nowMs(),
    );
    registry.register(handle, overwrite: overwrite);
    return handle;
  }

  /// Live (non-expired) handles. Evicts TTL-expired entries first.
  List<ArtifactHandle> list() {
    registry.evictExpired(_nowMs());
    return registry.list();
  }

  /// Pull artifact [name] to [destPath] on the fetching member's machine.
  ///
  /// [destPath] may be absolute or relative to the member inbox; either way the
  /// resolved path MUST stay inside the inbox (path-escape guard). Cross-machine
  /// transfers use chunked ranged copy with resume sidecars; same-machine uses
  /// [Filesystem.copyFile]. Throws an [ArtifactException] on rejection.
  Future<ArtifactFetchResult> fetch({
    required String fetcherMemberId,
    required String name,
    required String destPath,
    bool overwrite = false,
  }) async {
    registry.evictExpired(_nowMs());
    final handle = registry.byName(name.trim());
    if (handle == null) {
      throw UnknownArtifactException(name.trim());
    }

    final fetcherTargetId = _targetForMember(fetcherMemberId);
    final destFs = await _resolveFs(fetcherTargetId);
    final ctx = destFs.pathContext;
    final inbox = ctx.normalize(_inboxDirFor(fetcherMemberId));
    final resolvedDest = ctx.isAbsolute(destPath.trim())
        ? ctx.normalize(destPath.trim())
        : ctx.normalize(ctx.join(inbox, destPath.trim()));
    if (!ctx.isWithin(inbox, resolvedDest)) {
      throw ArtifactDestinationOutsideInboxException(
        destPath: resolvedDest,
        inboxDir: inbox,
      );
    }

    final destStat = await destFs.stat(resolvedDest);
    if (destStat.exists && !overwrite) {
      throw ArtifactDestinationExistsException(resolvedDest);
    }
    if (overwrite && destStat.exists) {
      await destFs.removeRecursive(resolvedDest);
    }

    final partial = partialPath(resolvedDest);
    final metaPath = partialMetaPath(resolvedDest);

    if (handle.targetId == fetcherTargetId) {
      await _deleteIfExists(destFs, partial);
      await _deleteIfExists(destFs, metaPath);
      await destFs.ensureDir(ctx.dirname(resolvedDest));
      await destFs.copyFile(handle.absolutePath, resolvedDest);
      final copied = await destFs.stat(resolvedDest);
      return ArtifactFetchResult(
        name: handle.name,
        finalPath: resolvedDest,
        sizeBytes: copied.size ?? handle.sizeBytes,
        publisherMemberId: handle.publisherMemberId,
      );
    }

    final srcFs = await _resolveFs(handle.targetId);
    final srcStat = await srcFs.stat(handle.absolutePath);
    if (!srcStat.exists || !srcStat.isFile) {
      await _deleteIfExists(destFs, partial);
      await _deleteIfExists(destFs, metaPath);
      throw ArtifactSourceUnreadableException(handle.absolutePath);
    }

    final liveSize = srcStat.size;
    final liveMtimeMs = srcStat.mtime?.millisecondsSinceEpoch;

    var bytesWritten = await _resolveResumeOffset(
      destFs: destFs,
      handle: handle,
      partial: partial,
      metaPath: metaPath,
      liveSize: liveSize,
      liveMtimeMs: liveMtimeMs,
    );

    await destFs.ensureDir(ctx.dirname(resolvedDest));

    if (liveSize != null && bytesWritten == liveSize) {
      return _finalizeRename(
        destFs: destFs,
        handle: handle,
        partial: partial,
        metaPath: metaPath,
        resolvedDest: resolvedDest,
        sizeBytes: liveSize,
      );
    }

    if (bytesWritten == 0) {
      await _writeMeta(
        destFs,
        metaPath,
        ArtifactPartialMeta(
          artifactName: handle.name,
          publisherMemberId: handle.publisherMemberId,
          sourceTargetId: handle.targetId,
          sourcePath: handle.absolutePath,
          expectedSizeBytes: liveSize,
          sourceMtimeMs: liveMtimeMs,
          bytesWritten: 0,
          chunkSize: chunkSize,
        ),
      );
    }

    while (true) {
      if (liveSize != null && bytesWritten >= liveSize) {
        if (bytesWritten > liveSize) {
          await _deleteIfExists(destFs, partial);
          await _deleteIfExists(destFs, metaPath);
          throw ArtifactSourceChangedException(
            detail: 'bytesWritten exceeded live source size',
          );
        }
        break;
      }

      final chunk = await srcFs.readBytesRange(
        handle.absolutePath,
        bytesWritten,
        chunkSize,
      );
      if (chunk == null) {
        await _deleteIfExists(destFs, partial);
        await _deleteIfExists(destFs, metaPath);
        throw ArtifactSourceUnreadableException(handle.absolutePath);
      }

      if (chunk.isEmpty) {
        if (liveSize != null && bytesWritten < liveSize) {
          await _deleteIfExists(destFs, partial);
          await _deleteIfExists(destFs, metaPath);
          throw ArtifactSourceChangedException(
            detail: 'source ended before expected size',
          );
        }
        break;
      }

      await destFs.appendBytes(partial, chunk);
      bytesWritten += chunk.length;

      if (liveSize != null && bytesWritten > liveSize) {
        await _deleteIfExists(destFs, partial);
        await _deleteIfExists(destFs, metaPath);
        throw ArtifactSourceChangedException(
          detail: 'bytesWritten exceeded live source size',
        );
      }

      await _writeMeta(
        destFs,
        metaPath,
        ArtifactPartialMeta(
          artifactName: handle.name,
          publisherMemberId: handle.publisherMemberId,
          sourceTargetId: handle.targetId,
          sourcePath: handle.absolutePath,
          expectedSizeBytes: liveSize,
          sourceMtimeMs: liveMtimeMs,
          bytesWritten: bytesWritten,
          chunkSize: chunkSize,
        ),
      );

      if (liveSize == null && chunk.length < chunkSize) {
        break;
      }
      if (liveSize != null && bytesWritten == liveSize) {
        break;
      }
    }

    return _finalizeRename(
      destFs: destFs,
      handle: handle,
      partial: partial,
      metaPath: metaPath,
      resolvedDest: resolvedDest,
      sizeBytes: bytesWritten,
    );
  }

  Future<int> _resolveResumeOffset({
    required Filesystem destFs,
    required ArtifactHandle handle,
    required String partial,
    required String metaPath,
    required int? liveSize,
    required int? liveMtimeMs,
  }) async {
    final raw = await destFs.readString(metaPath);
    if (raw == null) {
      await _deleteIfExists(destFs, partial);
      return 0;
    }

    final ArtifactPartialMeta meta;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _deleteIfExists(destFs, partial);
        await _deleteIfExists(destFs, metaPath);
        return 0;
      }
      meta = ArtifactPartialMeta.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      await _deleteIfExists(destFs, partial);
      await _deleteIfExists(destFs, metaPath);
      return 0;
    }

    final identityMatches =
        meta.artifactName == handle.name &&
        meta.publisherMemberId == handle.publisherMemberId &&
        meta.sourceTargetId == handle.targetId &&
        meta.sourcePath == handle.absolutePath;

    if (!identityMatches) {
      await _deleteIfExists(destFs, partial);
      await _deleteIfExists(destFs, metaPath);
      return 0;
    }

    if (liveSize != null && liveSize < meta.bytesWritten) {
      await _deleteIfExists(destFs, partial);
      await _deleteIfExists(destFs, metaPath);
      throw ArtifactSourceChangedException(
        detail: 'source shrunk below bytesWritten',
      );
    }

    final partialStat = await destFs.stat(partial);
    // Prefer real size when the backend reports it. When size is unknown
    // (legacy SFTP/WSL kind-only stat) but the partial file exists, trust
    // meta.bytesWritten so resume is not forced into a full restart.
    final int partialLength;
    if (!partialStat.exists || !partialStat.isFile) {
      partialLength = 0;
    } else if (partialStat.size != null) {
      partialLength = partialStat.size!;
    } else {
      partialLength = meta.bytesWritten;
    }

    if (meta.matchesLive(
      artifactName: handle.name,
      publisherMemberId: handle.publisherMemberId,
      sourceTargetId: handle.targetId,
      sourcePath: handle.absolutePath,
      liveSizeBytes: liveSize,
      liveMtimeMs: liveMtimeMs,
      partialLength: partialLength,
    )) {
      return meta.bytesWritten;
    }

    await _deleteIfExists(destFs, partial);
    await _deleteIfExists(destFs, metaPath);
    return 0;
  }

  Future<ArtifactFetchResult> _finalizeRename({
    required Filesystem destFs,
    required ArtifactHandle handle,
    required String partial,
    required String metaPath,
    required String resolvedDest,
    required int sizeBytes,
  }) async {
    // Zero-byte (and any rename-only path where the partial was never created)
    // must materialize an empty partial before rename, or dest never appears.
    final partialStat = await destFs.stat(partial);
    if (!partialStat.exists) {
      await destFs.writeBytes(partial, const []);
    }
    await destFs.rename(partial, resolvedDest);
    await _deleteIfExists(destFs, metaPath);
    return ArtifactFetchResult(
      name: handle.name,
      finalPath: resolvedDest,
      sizeBytes: sizeBytes,
      publisherMemberId: handle.publisherMemberId,
    );
  }

  Future<void> _writeMeta(
    Filesystem destFs,
    String metaPath,
    ArtifactPartialMeta meta,
  ) async {
    await destFs.writeString(metaPath, jsonEncode(meta.toJson()));
  }

  Future<void> _deleteIfExists(Filesystem fs, String path) async {
    final stat = await fs.stat(path);
    if (stat.exists) {
      await fs.removeRecursive(path);
    }
  }
}
