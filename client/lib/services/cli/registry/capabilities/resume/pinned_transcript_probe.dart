import '../../../../io/filesystem.dart';

/// Result of scanning transcript search roots for a pinned session id.
class PinnedTranscriptProbeResult {
  const PinnedTranscriptProbeResult({required this.exists, this.matchedPath});

  final bool exists;
  final String? matchedPath;
}

/// Probes `{root}/{layoutSegment}/{bucket}/{sessionId}.jsonl` under
/// [toolRoots]. When [matchDirectories] is true (resume detection), a matching
/// `{sessionId}/` directory also counts as "session exists"; transcript
/// location (history parse) must pass `false` so a workflow sidecar directory
/// can never shadow the real `.jsonl` file.
Future<PinnedTranscriptProbeResult> probePinnedTranscript({
  required Filesystem fs,
  required Iterable<String> toolRoots,
  required String sessionId,
  required String bucket,
  required List<String> layoutSegments,
  bool matchDirectories = true,
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
        if (matchDirectories) {
          final transcriptDir = path.join(bucketDir, id);
          if ((await fs.stat(transcriptDir)).isDirectory) {
            return PinnedTranscriptProbeResult(
              exists: true,
              matchedPath: transcriptDir,
            );
          }
        }
      }
      final scanned = await _scanLayoutBuckets(
        fs,
        layoutDir,
        id,
        matchDirectories: matchDirectories,
      );
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
  String sessionId, {
  required bool matchDirectories,
}) async {
  final path = fs.pathContext;
  try {
    final buckets = await fs.listDir(layoutDir);
    final dirMatches = <String>[];
    for (final bucket in buckets) {
      if (!bucket.isDirectory) continue;
      final bucketPath = path.join(layoutDir, bucket.name);
      final transcriptFile = path.join(bucketPath, '$sessionId.jsonl');
      if ((await fs.stat(transcriptFile)).isFile) return transcriptFile;
      if (!matchDirectories) continue;
      final transcriptDir = path.join(bucketPath, sessionId);
      if ((await fs.stat(transcriptDir)).isDirectory) {
        // Defer directory matches: a workflow sidecar bucket (e.g. a
        // `-client` sibling) may hold a `{sessionId}/` dir without any
        // transcript, and listDir order is not deterministic. A real
        // `.jsonl` in a later bucket must win, so collect dir matches and
        // only fall back to them if no file exists anywhere.
        dirMatches.add(transcriptDir);
      }
    }
    return dirMatches.isEmpty ? null : dirMatches.first;
  } on Object {
    return null;
  }
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
