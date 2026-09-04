import 'dart:async';

import '../../cubits/agent_attention_cubit.dart';
import '../agent_status/agent_attention_state.dart';
import '../agent_status/ask_user_question.dart';
import '../agent_status/ask_user_question_hook_gate.dart';
import '../agent_status/agent_status_event.dart';
import '../agent_status/exit_plan_mode.dart';
import '../agent_status/exit_plan_mode_hook_gate.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'runtime_event.dart';
import 'seat_event_stream.dart';

/// Applies a seat's durable runtime events to one derived state owner.
///
/// A projection cursor makes stream replay and duplicate publication harmless:
/// records at or behind the seat's last applied sequence are ignored.
class RuntimeEventProjection {
  RuntimeEventProjection({required this.onEvent});

  final void Function(RuntimeEventEnvelope event) onEvent;
  final Map<RuntimeSeatKey, int> _cursors = {};

  factory RuntimeEventProjection.attention({
    required AgentAttentionCubit attention,
    required bool Function(String sessionId, String memberId)
    resolveSkipPermissions,
    CliToolRegistry? registry,
  }) {
    final effectiveRegistry = registry ?? CliToolRegistry.builtIn();
    return RuntimeEventProjection(
      onEvent: (event) {
        if (event.kind == RuntimeEventKind.seatIdle) {
          attention.clearSeat(
            sessionId: event.seat.sessionId,
            memberId: event.seat.memberId,
          );
          attention.applyEvent(
            sessionId: event.seat.sessionId,
            memberId: event.seat.memberId,
            event: const AgentStatusEvent(state: AgentSeatAttention.done),
            skipPermissions: false,
          );
          return;
        }
        final raw = event.raw;
        if (raw == null) return;
        final status = effectiveRegistry
            .capability<ChatInteractionCapability>(event.cli)
            ?.normalize(raw);
        if (status == null) return;
        attention.applyEvent(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          event: status,
          skipPermissions: resolveSkipPermissions(
            event.seat.sessionId,
            event.seat.memberId,
          ),
        );
      },
    );
  }

  int cursorFor(RuntimeSeatKey seat) => _cursors[seat] ?? 0;

  StreamSubscription<RuntimeEventEnvelope> attach(
    SeatEventStream stream,
    RuntimeSeatKey seat,
  ) => stream.eventsFor(seat).listen(apply);

  void apply(RuntimeEventEnvelope event) {
    final cursor = cursorFor(event.seat);
    if (event.sequence <= cursor) return;
    _cursors[event.seat] = event.sequence;
    onEvent(event);
  }
}

abstract interface class RuntimeEventHookResponderProjection {
  Future<Map<String, Object?>?>? responseFor(RuntimeEventEnvelope event);
}

final class AskUserQuestionRuntimeEventProjection extends RuntimeEventProjection
    implements RuntimeEventHookResponderProjection {
  AskUserQuestionRuntimeEventProjection({
    required this.hookGate,
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn(),
       super(onEvent: (_) {});

  final AskUserQuestionHookGate hookGate;
  final CliToolRegistry _registry;
  final _responses = <(RuntimeSeatKey, int), Future<Map<String, Object?>?>>{};

  @override
  void apply(RuntimeEventEnvelope event) {
    final cursor = cursorFor(event.seat);
    super.apply(event);
    if (event.sequence <= cursor) return;
    final raw = event.raw;
    if (raw == null) return;
    final status = _registry
        .capability<ChatInteractionCapability>(event.cli)
        ?.normalize(raw);
    final toolUseId = status?.toolUseId?.trim() ?? '';
    final questions = status?.askUserQuestions;
    if (status?.hookEventName?.trim() != 'PreToolUse' ||
        !isAskUserQuestionTool(status?.toolName) ||
        toolUseId.isEmpty ||
        questions == null ||
        questions.isEmpty) {
      return;
    }
    final key = (event.seat, event.sequence);
    // A restore replay or duplicate publication must not re-register a stale
    // hold for the same seat/sequence whose HTTP request is long gone.
    // Kept after completion so [responseFor] still returns the held future;
    // entries are bounded by distinct PreToolUse sequences per seat.
    if (_responses.containsKey(key)) return;
    _responses[key] = hookGate
        .wait(
          sessionId: event.seat.sessionId,
          memberId: event.seat.memberId,
          toolUseId: toolUseId,
        )
        .then((reply) => reply?.toHookResponse());
  }

  @override
  Future<Map<String, Object?>?>? responseFor(RuntimeEventEnvelope event) =>
      _responses[(event.seat, event.sequence)];
}

final class ExitPlanModeRuntimeEventProjection extends RuntimeEventProjection
    implements RuntimeEventHookResponderProjection {
  ExitPlanModeRuntimeEventProjection({
    required this.hookGate,
    required this.permissionGate,
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn(),
       super(onEvent: (_) {});

  final ExitPlanModeHookGate hookGate;
  final ExitPlanPermissionRequestGate permissionGate;
  final CliToolRegistry _registry;
  final _responses = <(RuntimeSeatKey, int), Future<Map<String, Object?>?>>{};

  @override
  void apply(RuntimeEventEnvelope event) {
    final cursor = cursorFor(event.seat);
    super.apply(event);
    if (event.sequence <= cursor) return;
    final raw = event.raw;
    if (raw == null) return;
    final capability = _registry.capability<ChatInteractionCapability>(
      event.cli,
    );
    final status = capability?.normalize(raw);
    final toolUseId = status?.toolUseId?.trim() ?? '';
    final hasPlan =
        (status?.planText?.trim() ?? '').isNotEmpty ||
        (status?.planFilePath?.trim() ?? '').isNotEmpty;
    if (!isExitPlanModeTool(status?.toolName) ||
        !hasPlan ||
        capability?.supportsInChatApproval != true) {
      return;
    }
    final hookEvent = status?.hookEventName?.trim();
    final key = (event.seat, event.sequence);
    // A restore replay or duplicate publication must not re-register a stale
    // hold for the same seat/sequence whose HTTP request is long gone.
    // Kept after completion so [responseFor] still returns the held future;
    // entries are bounded by distinct PreToolUse sequences per seat.
    if (_responses.containsKey(key)) return;
    if (hookEvent == 'PreToolUse') {
      if (toolUseId.isEmpty) return;
      // A fresh plan prompt invalidates any remembered decision for the seat.
      permissionGate.forget(
        sessionId: event.seat.sessionId,
        memberId: event.seat.memberId,
      );
      _responses[key] = hookGate
          .wait(
            sessionId: event.seat.sessionId,
            memberId: event.seat.memberId,
            toolUseId: toolUseId,
          )
          .then((reply) => reply?.toHookResponse());
      return;
    }
    // Claude's native plan confirmation (`PermissionRequest`, no
    // tool_use_id): hold the hook so the chat card can return the official
    // `decision` object instead of falling through to the TUI prompt.
    if (hookEvent == 'PermissionRequest') {
      final fingerprint = exitPlanModeFingerprint(
        planText: status?.planText,
        planFilePath: status?.planFilePath,
      );
      if (fingerprint.isEmpty) return;
      _responses[key] = permissionGate
          .wait(
            sessionId: event.seat.sessionId,
            memberId: event.seat.memberId,
            planFingerprint: fingerprint,
          )
          .then((reply) => reply?.toHookResponse());
    }
  }

  @override
  Future<Map<String, Object?>?>? responseFor(RuntimeEventEnvelope event) =>
      _responses[(event.seat, event.sequence)];
}

/// Projects normalized hook status into the existing attention state owner.
///
/// The ingress gateway never touches the cubit directly; it publishes an
/// envelope and this projection applies its retained status payload.
final class AgentAttentionRuntimeEventProjection {
  AgentAttentionRuntimeEventProjection({
    required AgentAttentionCubit attention,
    required bool Function(String sessionId, String memberId)
    resolveSkipPermissions,
    CliToolRegistry? registry,
  }) : _projection = RuntimeEventProjection(
         onEvent: RuntimeEventProjection.attention(
           attention: attention,
           resolveSkipPermissions: resolveSkipPermissions,
           registry: registry,
         ).onEvent,
       );

  final RuntimeEventProjection _projection;

  int cursorFor(RuntimeSeatKey seat) => _projection.cursorFor(seat);

  StreamSubscription<RuntimeEventEnvelope> attach(
    SeatEventStream stream,
    RuntimeSeatKey seat,
  ) => _projection.attach(stream, seat);

  void apply(RuntimeEventEnvelope event) => _projection.apply(event);
}
