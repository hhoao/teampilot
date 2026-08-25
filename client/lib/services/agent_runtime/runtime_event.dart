import '../../models/team_config.dart';

enum RuntimeEventKind { promptSubmitted, statusReported }

enum RuntimeCorrelationStrength { exact, serializedPromptEpoch }

final class RuntimeSeatKey {
  const RuntimeSeatKey({required this.sessionId, required this.memberId});

  final String sessionId;
  final String memberId;

  @override
  bool operator ==(Object other) =>
      other is RuntimeSeatKey &&
      other.sessionId == sessionId &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(sessionId, memberId);
}

final class RuntimeEventEnvelopeDraft {
  const RuntimeEventEnvelopeDraft._({
    required this.seat,
    required this.cli,
    required this.kind,
    required this.occurredAt,
    this.prompt,
    this.raw,
    this.nativeEventId,
    this.correlationStrength = RuntimeCorrelationStrength.serializedPromptEpoch,
  });

  factory RuntimeEventEnvelopeDraft.promptSubmitted({
    required RuntimeSeatKey seat,
    required CliTool cli,
    required String prompt,
    required DateTime occurredAt,
    Map<String, Object?>? raw,
    String? nativeEventId,
    RuntimeCorrelationStrength correlationStrength =
        RuntimeCorrelationStrength.serializedPromptEpoch,
  }) => RuntimeEventEnvelopeDraft._(
    seat: seat,
    cli: cli,
    kind: RuntimeEventKind.promptSubmitted,
    prompt: prompt,
    raw: raw,
    nativeEventId: nativeEventId,
    occurredAt: occurredAt,
    correlationStrength: correlationStrength,
  );

  factory RuntimeEventEnvelopeDraft.statusReported({
    required RuntimeSeatKey seat,
    required CliTool cli,
    required DateTime occurredAt,
    required Map<String, Object?> raw,
    String? nativeEventId,
  }) => RuntimeEventEnvelopeDraft._(
    seat: seat,
    cli: cli,
    kind: RuntimeEventKind.statusReported,
    occurredAt: occurredAt,
    raw: raw,
    nativeEventId: nativeEventId,
  );

  final RuntimeSeatKey seat;
  final CliTool cli;
  final RuntimeEventKind kind;
  final DateTime occurredAt;
  final String? prompt;

  /// Retained native payload used by replay-safe state projections.
  final Map<String, Object?>? raw;

  /// Native id used to make replayed HTTP hook delivery idempotent.
  final String? nativeEventId;
  final RuntimeCorrelationStrength correlationStrength;
}

final class RuntimeEventEnvelope extends RuntimeEventEnvelopeDraft {
  const RuntimeEventEnvelope({
    required super.seat,
    required super.cli,
    required super.kind,
    required super.occurredAt,
    required this.sequence,
    super.prompt,
    super.raw,
    super.nativeEventId,
    super.correlationStrength,
  }) : super._();

  final int sequence;
}
