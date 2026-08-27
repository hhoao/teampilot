import '../../../cubits/agent_attention_cubit.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../team/terminal_activity_tracker.dart';
import '../terminal_launch_controller.dart';

/// Per-PTY context passed to observation handlers.
final class TerminalObservationSeat {
  TerminalObservationSeat({
    required this.sessionId,
    required this.memberId,
    this.cli,
    this.phase = TerminalLaunchPhase.idle,
    this.activityTracker,
    this.attention,
    this.skipPermissions,
    this.policy,
    this.failLaunch,
    this.confirmStarted,
    this.startupExecutable = '',
    this.validateLaunch = true,
  });

  final String sessionId;
  final String memberId;
  final CliTool? cli;
  TerminalLaunchPhase phase;
  final TerminalActivityTracker? activityTracker;
  final AgentAttentionCubit? attention;
  final bool Function()? skipPermissions;
  final TerminalBehaviorCapability? policy;
  final void Function(String message)? failLaunch;
  final void Function()? confirmStarted;
  final String startupExecutable;
  final bool validateLaunch;
}
