import '../../../../io/filesystem.dart';
import '../session_resume_capability.dart';

/// `clientPinned` strategy (claude, flashskyai): we pin our UUID with
/// `--session-id` at creation, so the native id == [ResumeContext.taskId] and a
/// resumable session is detected by the presence of the CLI's transcript file
/// `<taskId>.jsonl` (or `<taskId>/` dir) under the transcript search roots.
final class TranscriptResumeStrategy implements SessionResumeCapability {
  const TranscriptResumeStrategy();

  @override
  ResumeBinding get binding => ResumeBinding.clientPinned;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final id = ctx.taskId.trim();
    if (id.isEmpty) return null;
    final exists = await _transcriptExists(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: id,
      bucket: ctx.bucket,
    );
    return exists ? id : null;
  }
}

Future<bool> _transcriptExists({
  required Filesystem fs,
  required Iterable<String> toolRoots,
  required String sessionId,
  required String bucket,
}) async {
  final path = fs.pathContext;
  final memberSegment = '${path.separator}members${path.separator}';
  // Prefer member-scoped roots (mixed mode) before flat roots.
  final orderedRoots = [
    for (final root in toolRoots)
      if (root.contains(memberSegment)) root,
    for (final root in toolRoots)
      if (!root.contains(memberSegment)) root,
  ];
  for (final root in orderedRoots) {
    final projectsDir = path.join(root, 'projects');
    if (bucket.isNotEmpty) {
      final bucketDir = path.join(projectsDir, bucket);
      if ((await fs.stat(path.join(bucketDir, '$sessionId.jsonl'))).isFile) {
        return true;
      }
      if ((await fs.stat(path.join(bucketDir, sessionId))).isDirectory) {
        return true;
      }
    }
    if (await _scanProjects(fs, projectsDir, sessionId)) return true;
  }
  return false;
}

Future<bool> _scanProjects(
  Filesystem fs,
  String projectsDir,
  String sessionId,
) async {
  final path = fs.pathContext;
  try {
    final buckets = await fs.listDir(projectsDir);
    for (final bucket in buckets) {
      if (!bucket.isDirectory) continue;
      final bucketPath = path.join(projectsDir, bucket.name);
      if ((await fs.stat(path.join(bucketPath, '$sessionId.jsonl'))).isFile) {
        return true;
      }
      if ((await fs.stat(path.join(bucketPath, sessionId))).isDirectory) {
        return true;
      }
    }
  } on Object {
    return false;
  }
  return false;
}
