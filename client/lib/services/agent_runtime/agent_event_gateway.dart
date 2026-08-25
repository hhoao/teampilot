import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/team_config.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../agent_status/ask_user_question.dart';
import '../agent_status/ask_user_question_hook_gate.dart';
import '../agent_status/exit_plan_mode.dart';
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
    this.askUserHookGate,
    this.exitPlanModeHookGate,
    Iterable<RuntimeEventProjection> projections = const [],
    CliToolRegistry? registry,
    DateTime Function()? clock,
  }) : registry = registry ?? CliToolRegistry.builtIn(),
       _clock = clock ?? DateTime.now,
       _projections = List<RuntimeEventProjection>.unmodifiable(projections);

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
    return AgentEventGateway(
      journal: MemoryRuntimeEventJournal(),
      stream: SeatEventStream(),
      resolveCli: resolveCli,
      askUserHookGate: askUserHookGate,
      exitPlanModeHookGate: exitPlanModeHookGate,
      registry: effectiveRegistry,
      clock: clock,
      projections: [
        RuntimeEventProjection.attention(
          attention: attention,
          resolveSkipPermissions: resolveSkipPermissions,
          registry: effectiveRegistry,
        ),
      ],
    );
  }

  final RuntimeEventJournal journal;
  final SeatEventStream stream;
  final CliTool? Function(String sessionId, String memberId) resolveCli;
  final AskUserQuestionHookGate? askUserHookGate;
  final ExitPlanModeHookGate? exitPlanModeHookGate;
  final CliToolRegistry registry;
  final DateTime Function() _clock;
  final List<RuntimeEventProjection> _projections;
  final Map<RuntimeSeatKey, Set<String>> _nativeEventIds = {};
  final Set<RuntimeSeatKey> _loadedNativeEventIds = {};
  final Map<RuntimeSeatKey, Future<void>> _seatTails = {};
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
    stream.publish(event);
    return event;
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
    final raw = event.raw;
    if (raw == null) return null;
    final status = registry
        .capability<ChatInteractionCapability>(event.cli)
        ?.normalize(raw);
    if (status == null || status.hookEventName?.trim() != 'PreToolUse') {
      return null;
    }

    final toolUseId = status.toolUseId?.trim() ?? '';
    if (toolUseId.isEmpty) return null;
    if (isAskUserQuestionTool(status.toolName)) {
      final gate = askUserHookGate;
      final questions = status.askUserQuestions;
      if (gate == null || questions == null || questions.isEmpty) return null;
      final reply = await gate.wait(
        sessionId: event.seat.sessionId,
        memberId: event.seat.memberId,
        toolUseId: toolUseId,
      );
      return reply?.toHookResponse();
    }

    if (!isExitPlanModeTool(status.toolName)) return null;
    final gate = exitPlanModeHookGate;
    final hasPlan =
        (status.planText?.trim() ?? '').isNotEmpty ||
        (status.planFilePath?.trim() ?? '').isNotEmpty;
    final supportsApproval =
        registry
            .capability<ChatInteractionCapability>(event.cli)
            ?.supportsInChatApproval ??
        false;
    if (gate == null || !hasPlan || !supportsApproval) return null;
    final reply = await gate.wait(
      sessionId: event.seat.sessionId,
      memberId: event.seat.memberId,
      toolUseId: toolUseId,
    );
    return reply?.toHookResponse();
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
