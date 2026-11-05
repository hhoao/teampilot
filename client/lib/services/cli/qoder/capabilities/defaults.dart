import '../../../../models/hook_entry.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../chat/runtime/pty/fullscreen_cr_ack_config.dart';
import '../../../chat/runtime/pty/fullscreen_input_readiness.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/native_command_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';
import '../../registry/capabilities/team_behavior_capability.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/workspace_base_info_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_context.dart';
import '../../registry/launch/workspace_access.dart';

/// Qoder ships the same native coordination tools as CodeBuddy
/// (`TeamCreate`/`SendMessage`/`Task*`). Mixed TeamPilot teams coordinate over
/// teammate-bus, so the native names must be denied; they otherwise shadow
/// bus tools.
const qoderMixedNativeTeamDenyTools = <String>[
  'TeamCreate',
  'TeamDelete',
  'CreateChannel',
  'CreateColleague',
  'ListColleagues',
  'SendMessage',
  'MessageColleague',
  'SpeakInChannel',
  'ChannelTasks',
  'TaskCreate',
  'TaskUpdate',
  'TaskList',
  'TaskGet',
  'TaskStop',
  'TaskOutput',
];

const qoderMixedLeadExtraDenyTools = <String>['Agent'];

List<String> mixedDenyToolsForQoder({required bool isLead}) => [
  ...qoderMixedNativeTeamDenyTools,
  if (isLead) ...qoderMixedLeadExtraDenyTools,
];

final class QoderTeamBehavior implements TeamBehaviorCapability {
  const QoderTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => true;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};

  @override
  bool get requiresPtyFallback => false;

  @override
  bool get usesDoorbellPush => false;

  @override
  bool get defaultForceWaitBeforeStop => false;

  @override
  bool get usesClaudeRoster => false;

  @override
  bool get usesShellActivity => false;

  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}

final class QoderChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const QoderChatInteraction();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) => null;

  @override
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  ) => null;

  @override
  RuntimeCorrelationStrength get promptCorrelationStrength =>
      RuntimeCorrelationStrength.exact;

  @override
  List<HookEntry> managedHookEntries(RuntimeEventHookContext context) =>
      const [];

  @override
  bool get supportsStructuredAsk => false;

  @override
  bool get supportsInChatAnswer => false;

  @override
  bool get supportsMultiSelectInChat => false;

  @override
  bool get supportsMultiQuestionInChat => false;

  @override
  bool get supportsInChatPermissionReply => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.none;

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}

/// Required by the registry; ACP sessions never exercise PTY behavior.
final class QoderTerminalBehavior implements TerminalBehaviorCapability {
  const QoderTerminalBehavior();

  @override
  bool get supportsTurnInterrupt => true;

  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);

  @override
  bool get usesFullScreenInput => true;

  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 10);

  @override
  bool get usesGridPasteAck => true;

  @override
  bool get usesHookSubmitAck => true;

  @override
  bool get usesPasteBaseline => false;

  @override
  int get pasteZoneBottomPad => 0;

  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);

  @override
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.anchorCellClears;

  @override
  bool get mentionAutocompletePopup => false;

  @override
  FullscreenInputReadiness get inputReadiness =>
      FullscreenInputReadiness.bootFrameOnly;

  @override
  Duration get startupDeadline => const Duration(seconds: 15);
}

final class QoderWorkspaceBaseInfo extends WorkspaceBaseInfoCapabilityBase {
  const QoderWorkspaceBaseInfo();

  @override
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  ) => const [];
}

final class QoderNativeCommands implements NativeCommandCapability {
  const QoderNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(
      name: 'goal',
      description: NativeCommandDescription.goal,
      argumentHint: '<objective>',
    ),
    NativeCommand(
      name: 'compact',
      description: NativeCommandDescription.compact,
      argumentHint: '[instructions]',
    ),
    NativeCommand(name: 'plan', description: NativeCommandDescription.plan),
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
