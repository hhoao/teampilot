/// Kind of a published artifact. Only [file] is supported in v1; directory /
/// tar transfer is explicitly deferred (see remote-execution-architecture §4.2).
enum ArtifactKind {
  file;

  /// Parse a member-supplied `kind` string. Returns null for unknown / future
  /// kinds (e.g. `dir`) so the caller can reject with a clear message.
  static ArtifactKind? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return ArtifactKind.file;
    for (final k in ArtifactKind.values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

/// A cross-machine artifact handle stored by the bus. The bus records ONLY this
/// handle (publisher / target / path / name / size), never the bytes — the
/// local App moves the bytes on a later `fetch_artifact` (see §4.2).
class ArtifactHandle {
  const ArtifactHandle({
    required this.name,
    required this.publisherMemberId,
    required this.targetId,
    required this.absolutePath,
    required this.sizeBytes,
    required this.kind,
    required this.publishedAtMs,
  });

  /// Member-facing logical name used in `fetch_artifact(name, ...)`.
  final String name;

  /// Member that published the file (on its own machine).
  final String publisherMemberId;

  /// RuntimeTarget id the file lives on (publisher's machine).
  final String targetId;

  /// Absolute path of the source file on [targetId]'s filesystem (read-only).
  final String absolutePath;

  final int sizeBytes;
  final ArtifactKind kind;

  /// Epoch milliseconds the handle was registered; drives TTL eviction.
  final int publishedAtMs;

  @override
  String toString() =>
      'ArtifactHandle($name by $publisherMemberId on $targetId, '
      '$sizeBytes bytes)';
}
