import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// How a CLI's native session id is bound to our session. See
/// `docs/session-resume-architecture.md`.
enum ResumeBinding {
  /// We choose the id and pin it at creation (`--session-id`); native id ==
  /// our taskId. claude (`projects/`), flashskyai (`workspaces/`).
  clientPinned,

  /// The CLI mints the id and stores it in its per-session-isolated store; we
  /// capture it on reopen. codex, opencode, cursor.
  postCaptured,
}

/// Everything a resume strategy needs to detect a native session id,
/// independent of team-vs-personal mode.
class ResumeContext {
  const ResumeContext({
    required this.fs,
    required this.toolValue,
    required this.taskId,
    required this.env,
    required this.transcriptRoots,
    required this.bucket,
    this.persistedNativeId,
  });

  final Filesystem fs;
  final String toolValue;

  /// Our session/member UUID — the id pinned for `clientPinned` CLIs.
  final String taskId;

  /// Resolved launch environment (holds `CODEX_HOME` / `OPENCODE_DATA_DIR` /
  /// `CURSOR_CONFIG_DIR`, used to locate the per-session native store).
  final Map<String, String> env;

  /// claude-style transcript search roots (for `clientPinned` probing).
  /// Claude stores under `projects/`; flashskyai under `workspaces/`.
  final List<String> transcriptRoots;

  /// Workspace bucket derived from the working dir (claude transcript layout).
  final String bucket;

  /// The native id already recorded on the session-member binding, if any.
  final String? persistedNativeId;
}

/// Owns session-identity detection for one CLI: whether/how it pins, and how to
/// resolve the native session id to resume. Replaces the old claude-shaped
/// `TranscriptProbeCapability`.
abstract interface class SessionResumeCapability implements CliCapability {
  ResumeBinding get binding;

  /// Resolve the native id of an existing resumable session, or `null` when
  /// none exists yet. `clientPinned` probes the transcript file by our id;
  /// `postCaptured` scans the CLI's per-session-isolated store.
  Future<String?> detectNativeId(ResumeContext ctx);
}
