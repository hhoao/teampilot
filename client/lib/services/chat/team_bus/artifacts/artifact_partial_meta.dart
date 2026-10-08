/// Resume metadata for an in-progress artifact fetch (`{dest}.tp-partial.meta.json`).
///
/// Pure match/serialize helpers so transfer logic and tests can validate resume
/// without running a full fetch.
class ArtifactPartialMeta {
  const ArtifactPartialMeta({
    required this.artifactName,
    required this.publisherMemberId,
    required this.sourceTargetId,
    required this.sourcePath,
    required this.bytesWritten,
    required this.chunkSize,
    this.expectedSizeBytes,
    this.sourceMtimeMs,
  });

  final String artifactName;
  final String publisherMemberId;
  final String sourceTargetId;
  final String sourcePath;
  final int? expectedSizeBytes;
  final int? sourceMtimeMs;
  final int bytesWritten;

  /// Informational only — not part of [matchesLive].
  final int chunkSize;

  /// Returns true when this meta can resume against the live source and partial
  /// file on disk.
  ///
  /// Identity (name, publisher, target, path) must match. Size and mtime are
  /// compared only when both sides are known. [partialLength] must equal
  /// [bytesWritten]. [chunkSize] is not matched.
  bool matchesLive({
    required String artifactName,
    required String publisherMemberId,
    required String sourceTargetId,
    required String sourcePath,
    required int? liveSizeBytes,
    required int? liveMtimeMs,
    required int partialLength,
  }) {
    if (this.artifactName != artifactName ||
        this.publisherMemberId != publisherMemberId ||
        this.sourceTargetId != sourceTargetId ||
        this.sourcePath != sourcePath) {
      return false;
    }

    if (partialLength != bytesWritten) {
      return false;
    }

    if (expectedSizeBytes != null &&
        liveSizeBytes != null &&
        expectedSizeBytes != liveSizeBytes) {
      return false;
    }

    if (sourceMtimeMs != null &&
        liveMtimeMs != null &&
        sourceMtimeMs != liveMtimeMs) {
      return false;
    }

    return true;
  }

  Map<String, Object?> toJson() => {
    'artifactName': artifactName,
    'publisherMemberId': publisherMemberId,
    'sourceTargetId': sourceTargetId,
    'sourcePath': sourcePath,
    if (expectedSizeBytes != null) 'expectedSizeBytes': expectedSizeBytes,
    if (sourceMtimeMs != null) 'sourceMtimeMs': sourceMtimeMs,
    'bytesWritten': bytesWritten,
    'chunkSize': chunkSize,
  };

  factory ArtifactPartialMeta.fromJson(Map<String, Object?> json) {
    return ArtifactPartialMeta(
      artifactName: json['artifactName']! as String,
      publisherMemberId: json['publisherMemberId']! as String,
      sourceTargetId: json['sourceTargetId']! as String,
      sourcePath: json['sourcePath']! as String,
      expectedSizeBytes: json['expectedSizeBytes'] as int?,
      sourceMtimeMs: json['sourceMtimeMs'] as int?,
      bytesWritten: json['bytesWritten']! as int,
      chunkSize: json['chunkSize']! as int,
    );
  }
}
