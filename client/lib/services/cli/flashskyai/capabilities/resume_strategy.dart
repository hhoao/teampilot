import '../../registry/capabilities/session_resume_capability.dart';
import '../../registry/capabilities/resume/pinned_transcript_probe.dart';

/// flashskyai `clientPinned` resume: we pin our UUID with
/// `--session-id` at creation, so the native id == [ResumeContext.taskId] and a
/// resumable session is detected by the presence of the CLI's transcript file
/// `<taskId>.jsonl` (or `<taskId>/` dir) under `projects|workspaces/{bucket}/`.
final class FlashskyaiResumeStrategy implements SessionResumeCapability {
  const FlashskyaiResumeStrategy();

  // Real flashskyai installs use `projects/`; keep `workspaces` for older trees.
  static const _layoutSegments = ['projects', 'workspaces'];

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
