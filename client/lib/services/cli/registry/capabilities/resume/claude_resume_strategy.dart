import '../session_resume_capability.dart';
import 'pinned_transcript_probe.dart';

/// `clientPinned` strategy for Claude Code: we pin our UUID with
/// `--session-id` at creation, so the native id == [ResumeContext.taskId].
/// Claude stores transcripts under `{config}/projects/{cwd-bucket}/{id}.jsonl`
/// (not flashskyai's `workspaces/` layout).
final class ClaudeResumeStrategy implements SessionResumeCapability {
  const ClaudeResumeStrategy();

  static const _layoutSegments = ['projects'];

  @override
  ResumeBinding get binding => ResumeBinding.clientPinned;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final id = ctx.taskId.trim();
    if (id.isEmpty) return null;
    final exists = await pinnedTranscriptExists(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: id,
      bucket: ctx.bucket,
      layoutSegments: _layoutSegments,
    );
    return exists ? id : null;
  }
}
