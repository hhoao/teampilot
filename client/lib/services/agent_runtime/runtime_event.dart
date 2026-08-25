import '../../models/team_config.dart';

enum RuntimeEventKind { promptSubmitted }

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
    this.correlationStrength = RuntimeCorrelationStrength.serializedPromptEpoch,
  });

  factory RuntimeEventEnvelopeDraft.promptSubmitted({
    required RuntimeSeatKey seat,
    required CliTool cli,
    required String prompt,
    required DateTime occurredAt,
    RuntimeCorrelationStrength correlationStrength =
        RuntimeCorrelationStrength.serializedPromptEpoch,
  }) => RuntimeEventEnvelopeDraft._(
    seat: seat,
    cli: cli,
    kind: RuntimeEventKind.promptSubmitted,
    prompt: prompt,
    occurredAt: occurredAt,
    correlationStrength: correlationStrength,
  );

  final RuntimeSeatKey seat;
  final CliTool cli;
  final RuntimeEventKind kind;
  final DateTime occurredAt;
  final String? prompt;
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
    super.correlationStrength,
  }) : super._();

  final int sequence;
}
