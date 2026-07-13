import '../io/filesystem.dart';

/// Locate inputs for history adapters — same shape as resume locate fields,
/// without coupling to resume mutations.
class SessionHistoryContext {
  const SessionHistoryContext({
    required this.fs,
    required this.taskId,
    required this.env,
    required this.transcriptRoots,
    required this.bucket,
    this.persistedNativeId,
    this.workspaceId,
    this.sessionId,
    this.memberId,
    this.teamId,
    this.manifestDataRoot,
  });

  final Filesystem fs;
  final String taskId;
  final Map<String, String> env;
  final List<String> transcriptRoots;
  final String bucket;
  final String? persistedNativeId;
  final String? workspaceId;
  final String? sessionId;
  final String? memberId;
  final String? teamId;
  final String? manifestDataRoot;
}

/// Cache fingerprint for a history snapshot (typically transcript mtime).
typedef SessionHistoryCacheTokenResolver =
    Future<String?> Function(SessionHistoryContext ctx);
