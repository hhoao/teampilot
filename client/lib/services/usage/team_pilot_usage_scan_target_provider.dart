import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../chat/conversation/history/session_history_context_builder.dart';
import '../cli/registry/capabilities/session_usage_capability.dart';
import '../storage/home_storage.dart';
import 'usage_scan_target_provider.dart';

/// Turns TeamPilot sessions and seat bindings into scan contexts.
///
/// Session enumeration is injected as functions so this class does not depend
/// on a repository lifecycle. Production wiring lives in
/// `app/session_usage_services.dart`.
class TeamPilotUsageScanTargetProvider implements UsageScanTargetProvider {
  TeamPilotUsageScanTargetProvider({
    required HomeStorage storage,
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    SessionHistoryContextBuilder builder = const SessionHistoryContextBuilder(),
    this.scanAll = true,
    this.sinceMs,
  }) : _storage = storage,
       _loadSessions = loadSessions,
       _loadTeams = loadTeams,
       _builder = builder;

  final HomeStorage _storage;
  final Future<List<AppSession>> Function() _loadSessions;
  final Future<List<TeamProfile>> Function() _loadTeams;
  final SessionHistoryContextBuilder _builder;

  /// When false, sessions older than [sinceMs] are skipped.
  final bool scanAll;
  final int? sinceMs;

  @override
  Future<List<UsageScanContext>> targets() async {
    final sessions = await _loadSessions();
    final teams = await _loadTeams();
    final teamsById = {for (final team in teams) team.id: team};
    final out = <UsageScanContext>[];
    for (final session in sessions) {
      if (!scanAll) {
        final stamp = session.updatedAt != 0
            ? session.updatedAt
            : session.createdAt;
        if (sinceMs != null && stamp < sinceMs!) continue;
      }
      try {
        out.addAll(_targetsFor(session, teamsById[session.sessionTeam]));
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[usage] session target enumeration failed '
          'session=${session.sessionId}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return out;
  }

  List<UsageScanContext> _targetsFor(AppSession session, TeamProfile? team) {
    if (session.isSimple || session.members.isEmpty) {
      final cli = session.cli ?? team?.cli ?? CliTool.claude;
      final context = _build(session: session, cli: cli, memberId: '');
      return context == null ? const [] : [context];
    }

    final roster = team == null
        ? const <TeamMemberConfig>[]
        : sessionRosterMembers(session, team);
    final rosterById = {for (final member in roster) member.id: member};
    final out = <UsageScanContext>[];
    for (final binding in session.members) {
      final memberId = binding.rosterMemberId.trim();
      if (memberId.isEmpty) continue;
      final cli = binding.cli ?? rosterById[memberId]?.cli ?? session.cli;
      if (cli == null) continue;
      final context = _build(session: session, cli: cli, memberId: memberId);
      if (context != null) out.add(context);
    }
    return out;
  }

  UsageScanContext? _build({
    required AppSession session,
    required CliTool cli,
    required String memberId,
  }) {
    try {
      final work = session.workDirsForMember(
        memberId.isEmpty ? null : memberId,
        folders: session.folders,
        usesPosixPaths: _storage.usesPosixPaths,
      );
      final history = _builder.build(
        fs: _storage.fs,
        layout: _storage.context.layout,
        appDataRoot: _storage.appDataRoot,
        session: session,
        memberId: memberId,
        cli: cli,
        workingDirectory: work.workingDirectory,
        teamId: session.sessionTeam,
      );
      return UsageScanContext(
        fs: history.fs,
        cli: cli,
        env: history.env,
        transcriptRoots: history.transcriptRoots,
        taskId: history.taskId,
        nativeSessionId: history.persistedNativeId ?? '',
        sessionId: history.sessionId ?? session.sessionId,
        memberId: history.memberId ?? '',
        teamId: history.teamId ?? '',
        workingDirectory: work.workingDirectory,
        appDataRoot: _storage.appDataRoot,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[usage] target build failed session=${session.sessionId} '
        'member=$memberId cli=${cli.value}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
