import 'runtime_event.dart';

abstract interface class RuntimeEventJournal {
  Future<RuntimeEventEnvelope> append(RuntimeEventEnvelopeDraft draft);

  Stream<RuntimeEventEnvelope> replay(
    RuntimeSeatKey seat, {
    int afterSequence = 0,
  });
}

final class MemoryRuntimeEventJournal implements RuntimeEventJournal {
  final Map<RuntimeSeatKey, List<RuntimeEventEnvelope>> _events = {};

  @override
  Future<RuntimeEventEnvelope> append(RuntimeEventEnvelopeDraft draft) async {
    final seatEvents = _events.putIfAbsent(draft.seat, () => []);
    final event = RuntimeEventEnvelope(
      seat: draft.seat,
      cli: draft.cli,
      kind: draft.kind,
      occurredAt: draft.occurredAt,
      prompt: draft.prompt,
      correlationStrength: draft.correlationStrength,
      sequence: seatEvents.length + 1,
    );
    seatEvents.add(event);
    return event;
  }

  @override
  Stream<RuntimeEventEnvelope> replay(
    RuntimeSeatKey seat, {
    int afterSequence = 0,
  }) async* {
    for (final event in _events[seat] ?? const <RuntimeEventEnvelope>[]) {
      if (event.sequence > afterSequence) yield event;
    }
  }
}
