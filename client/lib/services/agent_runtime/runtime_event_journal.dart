import 'dart:convert';

import '../../models/team_config.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
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

/// Append-only newline-delimited JSON journal with one file per runtime seat.
///
/// A seat's append operation is serialized before its record is written, so a
/// returned envelope is always recoverable through [replay].
final class FileRuntimeEventJournal implements RuntimeEventJournal {
  FileRuntimeEventJournal({required this.journalRoot, Filesystem? fs})
    : _fs = fs ?? LocalFilesystem();

  final String journalRoot;
  final Filesystem _fs;

  static final Map<String, Future<void>> _seatLocks = {};

  String _fileFor(RuntimeSeatKey seat) => _fs.pathContext.join(
    journalRoot,
    '${_pathSegment(seat.sessionId)}--${_pathSegment(seat.memberId)}.jsonl',
  );

  String _lockKey(RuntimeSeatKey seat) =>
      '${identityHashCode(_fs)}:${_fileFor(seat)}';

  Future<T> _serialized<T>(RuntimeSeatKey seat, Future<T> Function() action) {
    final key = _lockKey(seat);
    final previous = _seatLocks[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    _seatLocks[key] = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<RuntimeEventEnvelope> append(RuntimeEventEnvelopeDraft draft) {
    return _serialized(draft.seat, () async {
      final sequence = await _lastSequence(draft.seat) + 1;
      final event = RuntimeEventEnvelope(
        seat: draft.seat,
        cli: draft.cli,
        kind: draft.kind,
        occurredAt: draft.occurredAt,
        prompt: draft.prompt,
        correlationStrength: draft.correlationStrength,
        sequence: sequence,
      );
      await _fs.ensureDir(journalRoot);
      await _fs.appendString(
        _fileFor(draft.seat),
        '${jsonEncode(_encode(event))}\n',
      );
      return event;
    });
  }

  @override
  Stream<RuntimeEventEnvelope> replay(
    RuntimeSeatKey seat, {
    int afterSequence = 0,
  }) async* {
    final events = await _readEvents(seat);
    for (final event in events) {
      if (event.sequence > afterSequence) yield event;
    }
  }

  Future<int> _lastSequence(RuntimeSeatKey seat) async {
    final events = await _readEvents(seat);
    return events.isEmpty ? 0 : events.last.sequence;
  }

  Future<List<RuntimeEventEnvelope>> _readEvents(RuntimeSeatKey seat) async {
    final content = await _fs.readString(_fileFor(seat));
    if (content == null || content.trim().isEmpty) {
      return <RuntimeEventEnvelope>[];
    }
    final events = <RuntimeEventEnvelope>[];
    for (final line in const LineSplitter().convert(content)) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          final event = _decode(Map<String, Object?>.from(decoded));
          if (event != null && event.seat == seat) events.add(event);
        }
      } on FormatException {
        // A partial trailing record is not durable and is ignored on replay.
      }
    }
    events.sort((a, b) => a.sequence.compareTo(b.sequence));
    return events;
  }
}

String _pathSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

Map<String, Object?> _encode(RuntimeEventEnvelope event) => {
  'sessionId': event.seat.sessionId,
  'memberId': event.seat.memberId,
  'cli': event.cli.name,
  'kind': event.kind.name,
  'occurredAt': event.occurredAt.toUtc().toIso8601String(),
  'prompt': event.prompt,
  'correlationStrength': event.correlationStrength.name,
  'sequence': event.sequence,
};

RuntimeEventEnvelope? _decode(Map<String, Object?> value) {
  final sessionId = value['sessionId'] as String?;
  final memberId = value['memberId'] as String?;
  final cliName = value['cli'] as String?;
  final kindName = value['kind'] as String?;
  final occurredAtText = value['occurredAt'] as String?;
  final sequence = (value['sequence'] as num?)?.toInt();
  if (sessionId == null ||
      memberId == null ||
      cliName == null ||
      kindName == null ||
      occurredAtText == null ||
      sequence == null) {
    return null;
  }
  final cli = _enumByName(CliTool.values, cliName);
  final kind = _enumByName(RuntimeEventKind.values, kindName);
  final correlationStrength = _enumByName(
    RuntimeCorrelationStrength.values,
    value['correlationStrength'] as String? ?? '',
  );
  final occurredAt = DateTime.tryParse(occurredAtText);
  if (cli == null ||
      kind == null ||
      correlationStrength == null ||
      occurredAt == null) {
    return null;
  }
  return RuntimeEventEnvelope(
    seat: RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
    cli: cli,
    kind: kind,
    occurredAt: occurredAt,
    prompt: value['prompt'] as String?,
    correlationStrength: correlationStrength,
    sequence: sequence,
  );
}

T? _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
