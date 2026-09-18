import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import 'session_persist_params.dart';

/// Identifies a shell that an existing-tab reconnect must reuse.
enum SessionShellAcquisition { personalResumeSession }

/// User intent to surface a persisted session in the workbench and connect it.
class SessionOpenRequest {
  const SessionOpenRequest({
    required this.session,
    this.workspace,
    this.team,
    this.member,
    this.repo,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.connectImmediately = true,
    this.scheduleConnect = true,
    this.waitForCompletion = false,
    this.preserveWorkbenchView = false,
    this.persistParams,
    this.preview,
    this.shellAcquisition,
  });

  final AppSession session;
  final Workspace? workspace;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final SessionRepository? repo;
  final String emptyDisplayTitleFallback;
  final bool connectImmediately;

  /// Internal materialization escape hatch for callers that will schedule a
  /// completion-aware member fan-out after the tab is surfaced.
  final bool scheduleConnect;

  /// Requests that the launch boundary settle before the caller continues.
  ///
  /// This is used by default-session materialization, where the request is
  /// routed through [SessionLaunchIntentPort] and cannot pass a scheduler
  /// option separately.
  final bool waitForCompletion;

  /// When true with [connectImmediately], keep the tab's current
  /// [SessionWorkbenchView] (e.g. Chat continue) instead of forcing Terminal.
  final bool preserveWorkbenchView;

  /// Overrides the derived preview surfacing: null derives from
  /// [connectImmediately] (and, for existing tabs, running state) as usual;
  /// `false` forces a persistent tab that never occupies — and therefore
  /// never replaces through — the focused group's replaceable preview slot
  /// (used by "open to the side").
  final bool? preview;

  /// When set, the session is staged in memory first; disk write runs in prepare.
  final SessionPersistParams? persistParams;

  /// Optional shell identity for reconnects that must attach to an already
  /// displayed shell instead of acquiring the default member shell.
  final SessionShellAcquisition? shellAcquisition;

  bool get isPersonal => session.sessionTeam.trim().isEmpty;

  SessionOpenRequest withSession(AppSession next) {
    return SessionOpenRequest(
      session: next,
      workspace: workspace,
      team: team,
      member: member,
      repo: repo,
      emptyDisplayTitleFallback: emptyDisplayTitleFallback,
      connectImmediately: connectImmediately,
      scheduleConnect: scheduleConnect,
      waitForCompletion: waitForCompletion,
      preserveWorkbenchView: preserveWorkbenchView,
      persistParams: persistParams,
      preview: preview,
      shellAcquisition: shellAcquisition,
    );
  }
}
