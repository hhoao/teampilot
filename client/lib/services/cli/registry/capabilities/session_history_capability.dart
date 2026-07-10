import '../../../io/filesystem.dart';
import '../cli_capability.dart';

enum SessionHistoryRole { user, assistant, tool, system }

enum SessionHistoryLoadStatus { ready, empty, error }

class SessionHistoryTurn {
  const SessionHistoryTurn({
    required this.role,
    required this.markdown,
    this.timestamp,
    this.toolName,
    this.collapsedByDefault = false,
  });

  final SessionHistoryRole role;
  final String markdown;
  final DateTime? timestamp;
  final String? toolName;
  final bool collapsedByDefault;
}

class SessionHistorySnapshot {
  const SessionHistorySnapshot({
    required this.turns,
    required this.status,
    this.errorMessage,
  });

  final List<SessionHistoryTurn> turns;
  final SessionHistoryLoadStatus status;
  final String? errorMessage;
}

/// Locate inputs for history adapters — same shape as [ResumeContext] fields
/// used for transcript discovery, without coupling to resume mutations.
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

abstract interface class SessionHistoryCapability implements CliCapability {
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx);
}
