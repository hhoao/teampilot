import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/team_config.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../agent_status/ask_user_question_hook_gate.dart';
import '../agent_status/exit_plan_mode_hook_gate.dart';
import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/capabilities/runtime_event_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'runtime_event.dart';
import 'runtime_event_journal.dart';
import 'runtime_event_projection.dart';
import 'seat_event_stream.dart';

/// Max POST body size for the runtime hook endpoint (~1 MiB).
const int agentEventMaxBodyBytes = 1024 * 1024;

/// The sole HTTP ingress for CLI runtime hooks.
///
/// It only normalizes, journals, and publishes events. State changes belong to
/// projections subscribed to [stream]; terminal input is deliberately outside
/// this boundary.
final class AgentEventGateway {
  AgentEventGateway({
    required this.journal,
    required this.stream,
    required this.resolveCli,
    Iterable<RuntimeEventProjection> projections = const [],
    Iterable<RuntimeEventHookResponderProjection> responders = const [],
    CliToolRegistry? registry,
    DateTime Function()? clock,
  }) : registry = registry ?? CliToolRegistry.builtIn(),
       _clock = clock ?? DateTime.now,
       _projections = List<RuntimeEventProjection>.unmodifiable(projections),
       _responders = List<RuntimeEventHookResponderProjection>.unmodifiable(
         responders,
       );

  /// Lightweight in-memory composition for focused endpoint tests.
  factory AgentEventGateway.forAttention({
    required AgentAttentionCubit attention,
    required CliTool? Function(String sessionId, String memberId) resolveCli,
    required bool Function(String sessionId, String memberId)
    resolveSkipPermissions,
    AskUserQuestionHookGate? askUserHookGate,
    ExitPlanModeHookGate? exitPlanModeHookGate,
    CliToolRegistry? registry,
    DateTime Function()? clock,
  }) {
    final effectiveRegistry = registry ?? CliToolRegistry.builtIn();
    final questionProjection = askUserHookGate == null
        ? null
        : AskUserQuestionRuntimeEventProjection(
            hookGate: askUserHookGate,
            registry: effectiveRegistry,
          );
    final planProjection = exitPlanModeHookGate == null
        ? null
        : ExitPlanModeRuntimeEventProjection(
            hookGate: exitPlanModeHookGate,
            registry: effectiveRegistry,
          );
    return AgentEventGateway(
      journal: MemoryRuntimeEventJournal(),
      stream: SeatEventStream(),
      resolveCli: resolveCli,
      registry: effectiveRegistry,
      clock: clock,
      projections: [
        RuntimeEventProjection.attention(
          attention: attention,
          resolveSkipPermissions: resolveSkipPermissions,
          registry: effectiveRegistry,
        ),
        if (questionProjection != null) questionProjection,
        if (planProjection != null) planProjection,
      ],
      responders: [
        if (questionProjection != null) questionProjection,
        if (planProjection != null) planProjection,
      ],
    );
  }

  final RuntimeEventJournal journal;
  final SeatEventStream stream;
  final CliTool? Function(String sessionId, String memberId) resolveCli;
  final CliToolRegistry registry;
  final DateTime Function() _clock;
  final List<RuntimeEventProjection> _projections;
  final List<RuntimeEventHookResponderProjection> _responders;
  final Map<RuntimeSeatKey, Set<String>> _nativeEventIds = {};
  final Set<RuntimeSeatKey> _loadedNativeEventIds = {};
  final Map<RuntimeSeatKey, Future<void>> _seatTails = {};
  final Map<String, Set<RuntimeSeatKey>> _knownSeatsBySession = {};
  final Map<RuntimeEventProjection, Set<RuntimeSeatKey>> _attachedSeats = {};
  final List<StreamSubscription<RuntimeEventEnvelope>> _subscriptions = [];

  /// Normalizes [body], appends its durable envelope, then publishes it.
  ///
  /// A native event id is a delivery idempotency key for one seat. The first
  /// successful call owns it; duplicates do not append or publish again.
  Future<RuntimeEventEnvelope?> handleJson(
    RuntimeSeatKey seat,
    Map<String, Object?> body,
  ) => _serialized(seat, () => _handleJson(seat, body));

  Future<RuntimeEventEnvelope?> _handleJson(
    RuntimeSeatKey seat,
    Map<String, Object?> body,
  ) async {
    final cli = resolveCli(seat.sessionId, seat.memberId);
    if (cli == null) return null;

    final nativeEventId = body['id']?.toString().trim() ?? '';
    if (nativeEventId.isNotEmpty) {
      await _loadNativeEventIds(seat);
      final ids = _nativeEventIds.putIfAbsent(seat, () => <String>{});
      if (ids.contains(nativeEventId)) return null;
    }

    final runtimeDraft = registry
        .capability<RuntimeEventCapability>(cli)
        ?.normalizeRuntimeEvent(body, seat, _clock());
    final hasStatus =
        registry.capability<ChatInteractionCapability>(cli)?.normalize(body) !=
        null;
    final draft = runtimeDraft == null
        ? (hasStatus
              ? RuntimeEventEnvelopeDraft.statusReported(
                  seat: seat,
                  cli: cli,
                  occurredAt: _clock(),
                  raw: body,
                  nativeEventId: nativeEventId.isEmpty ? null : nativeEventId,
                )
              : null)
        : RuntimeEventEnvelopeDraft.promptSubmitted(
            seat: runtimeDraft.seat,
            cli: runtimeDraft.cli,
            prompt: runtimeDraft.prompt ?? '',
            occurredAt: runtimeDraft.occurredAt,
            raw: body,
            nativeEventId: nativeEventId.isEmpty ? null : nativeEventId,
            correlationStrength: runtimeDraft.correlationStrength,
          );
    if (draft == null) return null;

    // Awaiting append is the durability boundary. Nothing observes this
    // envelope until its record is recoverable through RuntimeEventJournal.
    final event = await journal.append(draft);
    if (nativeEventId.isNotEmpty) {
      _nativeEventIds[seat]!.add(nativeEventId);
    }
    _attachProjections(event.seat);
    _rememberSeat(event.seat);
    stream.publish(event);
    return event;
  }

  /// Publishes a durable idle/reset event for one seat, or every known seat in
  /// a session when an established Windows keep-alive request omits X-Member.
  Future<void> publishIdle({
    required String sessionId,
    String? memberId,
  }) async {
    final trimmedMemberId = memberId?.trim() ?? '';
    final seats = trimmedMemberId.isNotEmpty
        ? <RuntimeSeatKey>{
            RuntimeSeatKey(sessionId: sessionId, memberId: trimmedMemberId),
          }
        : Set<RuntimeSeatKey>.of(_knownSeatsBySession[sessionId] ?? const {});
    for (final seat in seats) {
      await _serialized(seat, () async {
        final cli = resolveCli(seat.sessionId, seat.memberId);
        if (cli == null) return;
        final event = await journal.append(
          RuntimeEventEnvelopeDraft.seatIdle(
            seat: seat,
            cli: cli,
            occurredAt: _clock(),
          ),
        );
        _attachProjections(seat);
        _rememberSeat(seat);
        stream.publish(event);
      });
    }
  }

  void _rememberSeat(RuntimeSeatKey seat) {
    _knownSeatsBySession
        .putIfAbsent(seat.sessionId, () => <RuntimeSeatKey>{})
        .add(seat);
  }

  Future<void> _loadNativeEventIds(RuntimeSeatKey seat) async {
    if (!_loadedNativeEventIds.add(seat)) return;
    final ids = _nativeEventIds.putIfAbsent(seat, () => <String>{});
    await for (final event in journal.replay(seat)) {
      final id = event.nativeEventId?.trim() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
  }

  Future<T> _serialized<T>(RuntimeSeatKey seat, Future<T> Function() action) {
    final previous = _seatTails[seat] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _seatTails[seat] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_seatTails[seat], tail)) _seatTails.remove(seat);
      }),
    );
    return result;
  }

  void _attachProjections(RuntimeSeatKey seat) {
    for (final projection in _projections) {
      final seats = _attachedSeats.putIfAbsent(
        projection,
        () => <RuntimeSeatKey>{},
      );
      if (seats.add(seat)) {
        _subscriptions.add(projection.attach(stream, seat));
      }
    }
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// Best-effort HTTP adapter retaining the managed hook endpoint contract.
  /// Invalid payloads and unknown seats return 200 `{}` so hooks never loop.
  Future<void> handle(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
  }) async {
    try {
      final body = await _readJsonBody(request);
      if (body != null) {
        final queryEvent = request.uri.queryParameters['event']?.trim();
        final event = await handleJson(
          RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
          _withHookEventName(body, queryEvent),
        );
        final response = event == null ? null : await _heldHookResponse(event);
        if (response != null) {
          await _writeJson(request, response);
          return;
        }
      }
      await _writeJson(request, const <String, Object?>{});
    } catch (_) {
      try {
        await _writeJson(request, const <String, Object?>{});
      } catch (_) {}
    }
  }

  Future<Map<String, Object?>?> _heldHookResponse(
    RuntimeEventEnvelope event,
  ) async {
    for (final responder in _responders) {
      final pendingResponse = responder.responseFor(event);
      if (pendingResponse == null) continue;
      return await pendingResponse;
    }
    return null;
  }

  Map<String, Object?> _withHookEventName(
    Map<String, Object?> body,
    String? queryEvent,
  ) {
    final existing = body['hook_event_name']?.toString().trim() ?? '';
    if (existing.isNotEmpty) return body;
    final event = queryEvent?.trim() ?? '';
    return event.isEmpty ? body : {...body, 'hook_event_name': event};
  }

  Future<Map<String, Object?>?> _readJsonBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var overflow = false;
    await for (final chunk in request) {
      if (overflow) continue;
      builder.add(chunk);
      if (builder.length > agentEventMaxBodyBytes) {
        overflow = true;
        builder.clear();
      }
    }
    if (overflow) return null;
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
