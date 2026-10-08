import '../../../../models/hook_entry.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../io/filesystem.dart';
import '../../registry/capabilities/team_behavior_capability.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../../../chat/runtime/pty/fullscreen_cr_ack_config.dart';
import '../../../chat/runtime/pty/fullscreen_input_readiness.dart';

/// Gemini is not team-launchable in this phase: no native team identity, no
/// roster, no member agent preset. Mirrors the "unsupported" defaults of
/// [CodexTeamBehavior] for every surface.
final class GeminiTeamBehavior implements TeamBehaviorCapability {
  const GeminiTeamBehavior();

  @override
  bool get supportsNativeTeam => false;

  @override
  bool get longBlockingWaitForMessage => false;

  @override
  bool get supportsLocalStdioBridge => false;

  @override
  Set<String> get doneEventNames => const {};

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

/// Gemini has no structured ask / in-chat reply in this phase; runtime-event
/// normalization and managed hooks are no-ops (ACP task 8+ revisits these).
final class GeminiChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const GeminiChatInteraction();

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

/// Gemini CLI is an Ink full-screen TUI like Claude Code; conservative
/// defaults until grid automation is tuned against real output.
final class GeminiTerminalBehavior implements TerminalBehaviorCapability {
  const GeminiTerminalBehavior();

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

  // Gemini CLI emits a submit hook, so the CR submit is hook-confirmed like
  // every other built-in full-screen CLI (see the capability doc).
  @override
  bool get usesHookSubmitAck => true;

  // Cursor-specific paste-denominator baseline; gemini's mirror caret sits in
  // its composer, so the plain cursor input zone ACKs correctly.
  @override
  bool get usesPasteBaseline => false;

  // Gemini draws no footer below its input box.
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

/// Gemini has no TeamPilot plugin surface in this phase: no manifest layout,
/// no components, no marketplace consumption. Provisioning is a no-op.
final class GeminiPluginCapability implements PluginCapability {
  const GeminiPluginCapability();

  @override
  bool get writesAssembledMcp => false;

  @override
  PluginRuntimeOwnership get runtimeOwnership =>
      PluginRuntimeOwnership.teamPilot;

  @override
  PluginManifestPaths? get manifestPaths => null;

  @override
  List<String> get memberPluginsSubpath => const ['plugins'];

  @override
  Set<PluginComponentKind> get supported => const {};

  @override
  Future<void> provision(PluginProvisionContext ctx) async {}

  @override
  bool get consumesMarketplaces => false;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
