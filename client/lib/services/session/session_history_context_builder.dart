import '../cli/registry/capabilities/ai_history_capability.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../storage/runtime_layout.dart';
import 'session_history_context.dart';

/// Read-only locate context for AI transcript adapters.
///
/// Resolves the same on-disk isolation dirs a launch would use, without
/// calling `prepareLaunch` / `ConfigProfileService.prepare*` / PTY connect.
final class SessionHistoryContextBuilder {
  const SessionHistoryContextBuilder();

  SessionHistoryContext build({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String appDataRoot,
    required AppSession session,
    required String memberId,
    required CliTool cli,
    String? workingDirectory,
    String? teamId,
    String? persistedNativeId,
    String? taskId,
  }) {
    final workspaceId = session.workspaceId.trim();
    final sessionId = session.sessionId.trim();
    if (workspaceId.isEmpty) {
      throw StateError('SessionHistoryContextBuilder requires workspaceId');
    }
    if (sessionId.isEmpty) {
      throw StateError('SessionHistoryContextBuilder requires sessionId');
    }

    final trimmedMember = memberId.trim();
    final isSimple = trimmedMember.isEmpty;
    final resolvedTeamId = (teamId ?? session.sessionTeam).trim();
    if (!isSimple && resolvedTeamId.isEmpty) {
      appLogger.e(
        '[session-history] context build missing teamId for member '
        '$trimmedMember session=$sessionId',
      );
      throw StateError(
        'SessionHistoryContextBuilder requires teamId for member $trimmedMember',
      );
    }
    final effectiveTeamId = isSimple ? null : resolvedTeamId;

    final String resolvedTaskId;
    final String? resolvedNativeId;
    String? resolvedMemberId;

    if (isSimple) {
      resolvedTaskId = (taskId?.trim().isNotEmpty == true)
          ? taskId!.trim()
          : sessionId;
      resolvedNativeId = persistedNativeId?.trim().isNotEmpty == true
          ? persistedNativeId!.trim()
          : session.nativeSessionIds[cli.value];
      resolvedMemberId = null;
    } else {
      final binding = session.requireBinding(trimmedMember);
      final fromBinding = binding.taskId.trim();
      final fromArg = taskId?.trim() ?? '';
      final chosen = fromArg.isNotEmpty ? fromArg : fromBinding;
      if (chosen.isEmpty) {
        appLogger.e(
          '[session-history] context build missing taskId for member '
          '$trimmedMember session=$sessionId',
        );
        throw StateError(
          'SessionHistoryContextBuilder requires taskId for member $trimmedMember',
        );
      }
      resolvedTaskId = chosen;
      resolvedNativeId = persistedNativeId?.trim().isNotEmpty == true
          ? persistedNativeId!.trim()
          : binding.nativeSessionIds[cli.value];
      resolvedMemberId = trimmedMember;
    }

    final cwd = (workingDirectory?.trim().isNotEmpty == true)
        ? workingDirectory!.trim()
        : session.firstFolderPath;
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(cwd);

    final tools = [cli.value];
    final transcriptRoots = isSimple
        ? _standaloneTranscriptSearchRoots(
            layout: layout,
            workspaceId: workspaceId,
            sessionId: sessionId,
            tools: tools,
          )
        : layout.transcriptSearchRoots(
            workspaceId: workspaceId,
            sessionId: sessionId,
            profileId: effectiveTeamId,
            memberId: resolvedMemberId,
            tools: tools,
          );

    final env = _envForCli(
      layout: layout,
      cli: cli,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: resolvedMemberId,
      teamId: effectiveTeamId,
    );

    return SessionHistoryContext(
      fs: fs,
      taskId: resolvedTaskId,
      env: env,
      transcriptRoots: transcriptRoots,
      bucket: bucket,
      persistedNativeId: resolvedNativeId,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: resolvedMemberId,
      teamId: effectiveTeamId,
      manifestDataRoot: appDataRoot,
    );
  }

  Map<String, String> _envForCli({
    required RuntimeLayout layout,
    required CliTool cli,
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) {
    final registry = CliToolRegistry.builtIn();
    final cap = registry.capability<AiHistoryCapability>(cli);
    if (cap == null) return const {};
    // The session CONFIG_DIR is resolved by the CLI's layout capability
    // (cursor isolates a fake $HOME; every other CLI uses the standard
    // sessionRuntimeToolDir) so this builder never special-cases a CLI.
    final toolRoot = sessionConfigDirForTool(
      cli,
      layout,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      teamId: teamId,
      registry: registry,
    );
    return cap.sessionEnv(toolRoot: toolRoot);
  }

  /// Matches [SessionLifecycleService] simple-mode transcript roots (no
  /// identity layer).
  List<String> _standaloneTranscriptSearchRoots({
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required Iterable<String> tools,
  }) {
    final tt = tools.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      for (final tool in tt) layout.appToolRoot(tool),
      for (final tool in tt) layout.workspaceConfigToolDir(workspaceId, tool),
      for (final tool in tt)
        layout.sessionRuntimeToolDir(workspaceId, sessionId, tool),
    ];
  }
}
