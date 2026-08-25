import 'dart:async';

import '../../cubits/agent_attention_cubit.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'runtime_event.dart';
import 'seat_event_stream.dart';

/// Applies a seat's durable runtime events to one derived state owner.
///
/// A projection cursor makes stream replay and duplicate publication harmless:
/// records at or behind the seat's last applied sequence are ignored.
final class RuntimeEventProjection {
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
