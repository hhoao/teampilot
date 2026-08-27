import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

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

  /// Seats with at least one durable record in [sessionId]. Recovery uses
  /// this to open/replay every seat of a session without knowing its roster.
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId);
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
      raw: draft.raw,
      nativeEventId: draft.nativeEventId,
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

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) async => {
    for (final seat in _events.keys)
      if (seat.sessionId == sessionId) seat,
  };
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

  @visibleForTesting
  static int get activeSeatLockCount => _seatLocks.length;

  String _fileFor(RuntimeSeatKey seat) => _fs.pathContext.join(
    journalRoot,
    _pathSegment(seat.sessionId),
    '${_pathSegment(seat.memberId)}.jsonl',
  );

  String _lockKey(RuntimeSeatKey seat) => _fileFor(seat);

  Future<T> _serialized<T>(RuntimeSeatKey seat, Future<T> Function() action) {
    final key = _lockKey(seat);
    final previous = _seatLocks[key] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _seatLocks[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_seatLocks[key], tail)) {
          _seatLocks.remove(key);
        }
      }),
    );
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
        raw: draft.raw,
        nativeEventId: draft.nativeEventId,
        correlationStrength: draft.correlationStrength,
        sequence: sequence,
      );
      await _fs.ensureDir(
        _fs.pathContext.dirname(_fileFor(draft.seat)),
      );
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

  /// Each seat's journal lives at `{session}/{member}.jsonl`, so only that
  /// session's directory is scanned to recover its seats.
  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) async {
    final sessionDir = _fs.pathContext.join(
      journalRoot,
      _pathSegment(sessionId),
    );
    final stat = await _fs.stat(sessionDir);
    if (!stat.exists || !stat.isDirectory) return const {};
    final seats = <RuntimeSeatKey>{};
    for (final entry in await _fs.listDir(sessionDir)) {
      if (entry.isDirectory || !entry.name.endsWith('.jsonl')) continue;
      final content = await _fs.readString(
        _fs.pathContext.join(sessionDir, entry.name),
      );
      final firstLine = content == null
          ? null
          : const LineSplitter()
              .convert(content)
              .where((line) => line.trim().isNotEmpty)
              .firstOrNull;
      if (firstLine == null) continue;
      try {
        final decoded = jsonDecode(firstLine);
        if (decoded is! Map) continue;
        final memberId = decoded['memberId']?.toString() ?? '';
        if (memberId.isEmpty) continue;
        seats.add(
          RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
        );
      } on FormatException {
        continue;
      }
    }
    return seats;
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
  'raw': event.raw,
  'nativeEventId': event.nativeEventId,
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
    raw: _stringKeyedMap(value['raw']),
    nativeEventId: value['nativeEventId'] as String?,
    correlationStrength: correlationStrength,
    sequence: sequence,
  );
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, entry) => MapEntry(key.toString(), entry));
}

T? _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
