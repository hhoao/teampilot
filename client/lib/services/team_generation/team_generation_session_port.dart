import '../../models/app_session.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../utils/team/team_member_naming.dart';

/// Canonical kickoff envelope delivered to the visible Builder session.
String buildTeamGenerationKickoff(String originalPrompt) =>
    'Build and launch the optimal TeamPilot team for the task below.\n'
    'Follow the managed Team Builder skill and use Team Composer until '
    'finalize_team_generation succeeds.\n\n'
    '$originalPrompt';

/// the cubit adapter lives in `cubits/team/`.
abstract interface class TeamGenerationSessionPort {
  /// Creates the purpose-tagged Simple builder session and surfaces it in the
  /// workbench (same visibility contract as a normal landing send).
  Future<SessionPortOpenResult> createBuilder({
    required Workspace workspace,
    required SimpleLaunchIdentity identity,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String workflowId,
    required String fixedSessionId,
    required String expertKey,
    String emptyDisplayTitleFallback = 'Team Builder',
    bool preserveWorkbenchView = false,
  });

  /// Creates (or reopens) the destination team session. Returns [opened]
  /// exactly when the tab is surfaced and the team roster is ready to stage.
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  });

  Future<SessionPortOpenResult> open(String sessionId);

  Future<void> select(String sessionId);

  Future<AppSession?> sessionById(String sessionId);

  /// Resolves when the lead's PTY surface can accept input.
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  });

  /// Persists the visible user-history bubble before its tracked PTY submit.
  /// [deliveryId] correlates the pending record with the durable delivery.
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  });

  /// Tracked direct-to-PTY delivery with an explicit idempotency id.
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  });

  /// Purpose/workflow-checked builder deletion; never accepts arbitrary ids
  /// from MCP input (validated by the caller against the job).
  Future<bool> deleteBuilder(String sessionId, String workflowId);

  /// Per-session activity stream used by the idle waiter.
  Stream<PortActivity> activityStream(String sessionId);
}

final class SessionPortOpenResult {
  const SessionPortOpenResult({required this.status, this.sessionId});

  /// 'opened' | 'blocked...' | 'skipped' — mirrors SessionOpenStatus values
  /// without importing the cubit layer here.
  final String status;
  final String? sessionId;

  bool get opened => status == 'opened';
}

final class PortDeliveryOutcome {
  const PortDeliveryOutcome({required this.result, this.deliveryState = ''});

  /// 'submitted' | 'dropped' | 'failed'.
  final String result;
  final String deliveryState;

  bool get submitted => result == 'submitted';
  bool get unknown =>
      result == 'dropped' ||
      deliveryState == 'submitIssued' ||
      deliveryState == 'submittedUnknown';

  /// Kickoff may proceed when CR ACK is flaky but the prompt likely landed.
  bool get acceptedForKickoff => submitted || unknown;
}

/// Ready/busy activity signal per session.
final class PortActivity {
  const PortActivity({required this.sessionId, required this.readyToChat});

  final String sessionId;
  final bool readyToChat;
}

/// Canonical member ids used by the port adapter.
abstract final class TeamGenerationPortMembers {
  static String get lead => TeamMemberNaming.teamLeadName;
}
