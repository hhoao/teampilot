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
///
/// The pinned [bucket] is a hint, not an authority: the same session id may
/// exist under several buckets (e.g. a residual stub in the main-repo bucket
/// plus the real transcript in a worktree bucket), and `listDir` order is not
/// deterministic. Files are ranked by size — the fullest `.jsonl` wins — and a
/// `{sessionId}/` directory match is used only when no file exists anywhere.
/// Equal-size matches fall back to the pinned [bucket], so scanning stays
/// deterministic regardless of `listDir` order.
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

  for (final root in orderedRoots) {
    for (final layoutSegment in layoutSegments) {
      final layoutDir = path.join(root, layoutSegment);
      final scanned = await _scanLayoutBuckets(
        fs,
        layoutDir,
        id,
        matchDirectories: matchDirectories,
        pinnedBucket: bucket,
      );
      if (scanned != null) {
        return PinnedTranscriptProbeResult(exists: true, matchedPath: scanned);
      }
    }
  }
  return const PinnedTranscriptProbeResult(exists: false);
}

/// Scans every bucket under [layoutDir] for [sessionId]. Returns the fullest
/// `.jsonl` file (largest bytes) — so a residual metadata-only stub in one
/// bucket never shadows the real transcript in another — or, when no file
/// exists anywhere, the first `{sessionId}/` directory match. Equal-size files
/// (and equal dir matches) prefer the pinned [pinnedBucket], so the result
/// never depends on non-deterministic `listDir` order.
Future<String?> _scanLayoutBuckets(
  Filesystem fs,
  String layoutDir,
  String sessionId, {
  required bool matchDirectories,
  required String pinnedBucket,
}) async {
  final path = fs.pathContext;
  try {
    final buckets = await fs.listDir(layoutDir);
    String? bestFile;
    var bestSize = -1;
    var bestIsPinned = false;
    String? firstDir;
    var firstDirIsPinned = false;
    for (final bucket in buckets) {
      if (!bucket.isDirectory) continue;
      final isPinned = bucket.name == pinnedBucket;
      final bucketPath = path.join(layoutDir, bucket.name);
      final transcriptFile = path.join(bucketPath, '$sessionId.jsonl');
      final fileStat = await fs.stat(transcriptFile);
      if (fileStat.isFile) {
        final size = fileStat.size ?? 0;
        if (size > bestSize ||
            (bestFile != null && size == bestSize && isPinned && !bestIsPinned)) {
          bestSize = size;
          bestFile = transcriptFile;
          bestIsPinned = isPinned;
        }
        continue;
      }
      if (!matchDirectories) continue;
      final transcriptDir = path.join(bucketPath, sessionId);
      if ((await fs.stat(transcriptDir)).isDirectory) {
        if (firstDir == null || (isPinned && !firstDirIsPinned)) {
          firstDir = transcriptDir;
          firstDirIsPinned = isPinned;
        }
      }
    }
    return bestFile ?? firstDir;
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
