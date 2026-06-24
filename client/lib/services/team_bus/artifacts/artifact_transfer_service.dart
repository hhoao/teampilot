import '../../io/filesystem.dart';
import 'artifact_exceptions.dart';
import 'artifact_handle.dart';
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
/// **local App** is the one process that can reach both filesystems, so it reads
/// from the publisher's target fs and writes into the fetcher's target fs.
///
/// All side-effecting dependencies are injected so this is unit-tested with fake
/// filesystems and no real SSH:
/// - [resolveFs] — target id → its [Filesystem] (wraps `RuntimeContextRegistry`).
/// - [targetForMember] — member id → the RuntimeTarget id it runs on.
/// - [inboxDirFor] — member id → its session inbox dir (the only place a fetch
///   may write; enforced by a path-escape guard).
/// - [maxBytes] — hard size cap (bytes are buffered whole; no base64 ever rides
///   the bus). v1 buffers the whole file — streaming is a future increment.
class ArtifactTransferService {
  ArtifactTransferService({
    required this.registry,
    required Future<Filesystem> Function(String targetId) resolveFs,
    required String Function(String memberId) targetForMember,
    required String Function(String memberId) inboxDirFor,
    this.maxBytes = defaultMaxBytes,
    int Function()? nowMs,
  })  : _resolveFs = resolveFs,
        _targetForMember = targetForMember,
        _inboxDirFor = inboxDirFor,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// 256 MiB. Bytes are buffered in memory during a transfer, so this also
  /// bounds peak memory per fetch.
  static const int defaultMaxBytes = 256 * 1024 * 1024;

  final ArtifactRegistry registry;
  final int maxBytes;
  final Future<Filesystem> Function(String targetId) _resolveFs;
  final String Function(String memberId) _targetForMember;
  final String Function(String memberId) _inboxDirFor;
  final int Function() _nowMs;

  /// Register a handle to [path] on [publisherMemberId]'s own machine. Validates
  /// the source is a regular file and (when the backend reports a size) within
  /// the cap; never moves bytes. Throws an [ArtifactException] on rejection.
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
    if (size >= 0 && size > maxBytes) {
      throw ArtifactTooLargeException(sizeBytes: size, maxBytes: maxBytes);
    }
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
  /// resolved path MUST stay inside the inbox (path-escape guard). The publisher
  /// file is read-only; the App reads its bytes from the publisher fs and writes
  /// them into the fetcher fs. Throws an [ArtifactException] on rejection.
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

    final srcFs = await _resolveFs(handle.targetId);
    final bytes = await srcFs.readBytes(handle.absolutePath);
    if (bytes == null) {
      throw ArtifactSourceUnreadableException(handle.absolutePath);
    }
    if (bytes.length > maxBytes) {
      throw ArtifactTooLargeException(
        sizeBytes: bytes.length,
        maxBytes: maxBytes,
      );
    }

    await destFs.ensureDir(ctx.dirname(resolvedDest));
    await destFs.writeBytes(resolvedDest, bytes);

    return ArtifactFetchResult(
      name: handle.name,
      finalPath: resolvedDest,
      sizeBytes: bytes.length,
      publisherMemberId: handle.publisherMemberId,
    );
  }
}
