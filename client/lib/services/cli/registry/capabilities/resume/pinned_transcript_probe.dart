import '../../../../io/filesystem.dart';

/// Result of scanning transcript search roots for a pinned session id.
class PinnedTranscriptProbeResult {
  const PinnedTranscriptProbeResult({required this.exists, this.matchedPath});

  final bool exists;
  final String? matchedPath;
}

/// Probes `{root}/{layoutSegment}/{bucket}/{sessionId}.jsonl` (or a matching
/// `{sessionId}/` directory) under [toolRoots].
Future<PinnedTranscriptProbeResult> probePinnedTranscript({
  required Filesystem fs,
  required Iterable<String> toolRoots,
  required String sessionId,
  required String bucket,
  required List<String> layoutSegments,
}) async {
  final id = sessionId.trim();
  if (id.isEmpty) {
    return const PinnedTranscriptProbeResult(exists: false);
  }

  final path = fs.pathContext;
  final memberSegment = '${path.separator}members${path.separator}';
  final orderedRoots = [
    for (final root in toolRoots)
      if (root.contains(memberSegment)) root,
    for (final root in toolRoots)
      if (!root.contains(memberSegment)) root,
  ];

  final rootsTried = <String>[];
  for (final root in orderedRoots) {
    rootsTried.add(root);
    for (final layoutSegment in layoutSegments) {
      final layoutDir = path.join(root, layoutSegment);
      if (bucket.isNotEmpty) {
        final bucketDir = path.join(layoutDir, bucket);
        final transcriptFile = path.join(bucketDir, '$id.jsonl');
        if ((await fs.stat(transcriptFile)).isFile) {
          return PinnedTranscriptProbeResult(
            exists: true,
            matchedPath: transcriptFile,
          );
        }
        final transcriptDir = path.join(bucketDir, id);
        if ((await fs.stat(transcriptDir)).isDirectory) {
          return PinnedTranscriptProbeResult(
            exists: true,
            matchedPath: transcriptDir,
          );
        }
      }
      final scanned = await _scanLayoutBuckets(fs, layoutDir, id);
      if (scanned != null) {
        return PinnedTranscriptProbeResult(exists: true, matchedPath: scanned);
      }
    }
  }
  return const PinnedTranscriptProbeResult(exists: false);
}

Future<String?> _scanLayoutBuckets(
  Filesystem fs,
  String layoutDir,
  String sessionId,
) async {
  final path = fs.pathContext;
  try {
    final buckets = await fs.listDir(layoutDir);
    for (final bucket in buckets) {
      if (!bucket.isDirectory) continue;
      final bucketPath = path.join(layoutDir, bucket.name);
      final transcriptFile = path.join(bucketPath, '$sessionId.jsonl');
      if ((await fs.stat(transcriptFile)).isFile) return transcriptFile;
      final transcriptDir = path.join(bucketPath, sessionId);
      if ((await fs.stat(transcriptDir)).isDirectory) return transcriptDir;
    }
  } on Object {
    return null;
  }
  return null;
}

Future<bool> pinnedTranscriptExists({
  required Filesystem fs,
  required Iterable<String> toolRoots,
  required String sessionId,
  required String bucket,
  required List<String> layoutSegments,
}) async {
  final result = await probePinnedTranscript(
    fs: fs,
    toolRoots: toolRoots,
    sessionId: sessionId,
    bucket: bucket,
    layoutSegments: layoutSegments,
  );
  return result.exists;
}
