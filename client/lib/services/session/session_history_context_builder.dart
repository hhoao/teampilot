import 'package:path/path.dart' as p;

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/session_history_capability.dart';
import '../io/filesystem.dart';
import '../provider/codex/codex_session_config_dir.dart';
import '../provider/cursor/cursor_session_config_dir.dart';
import '../storage/runtime_layout.dart';

/// Read-only locate context for [SessionHistoryCapability] adapters.
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
    assert(
      workspaceId.isNotEmpty,
      'SessionHistoryContextBuilder requires workspaceId',
    );
    assert(
      sessionId.isNotEmpty,
      'SessionHistoryContextBuilder requires sessionId',
    );

    final trimmedMember = memberId.trim();
    final isSimple = trimmedMember.isEmpty;
    final resolvedTeamId = (teamId ?? session.sessionTeam).trim();
    if (!isSimple) {
      assert(
        resolvedTeamId.isNotEmpty,
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
      assert(
        chosen.isNotEmpty,
        'SessionHistoryContextBuilder requires taskId for member $trimmedMember',
      );
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
    switch (cli) {
      case CliTool.codex:
        return {
          'CODEX_HOME': CodexSessionConfigDir.resolve(
            layout,
            workspaceId: workspaceId,
            sessionId: sessionId,
            memberId: memberId,
          ),
        };
      case CliTool.opencode:
        return {
          'OPENCODE_DATA_DIR': layout.sessionRuntimeToolDir(
            workspaceId,
            sessionId,
            'opencode',
            memberId: memberId,
          ),
        };
      case CliTool.cursor:
        final cursorRoot = CursorSessionConfigDir.resolve(
          layout,
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: memberId,
          teamId: teamId,
        );
        return {
          'CURSOR_CONFIG_DIR': cursorRoot,
          'HOME': p.dirname(cursorRoot),
          'USERPROFILE': p.dirname(cursorRoot),
        };
      case CliTool.claude:
      case CliTool.flashskyai:
        // Adapters locate via transcriptRoots + bucket; no env keys required.
        return const {};
    }
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
