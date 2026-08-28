import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
///
/// Sequence assignment and incremental replay use a process-wide cursor keyed
/// by file path: a matching `stat.size` hits the in-memory last sequence and
/// line-end offsets; a cold start reads only the last complete line.
final class FileRuntimeEventJournal implements RuntimeEventJournal {
  FileRuntimeEventJournal({required this.journalRoot, Filesystem? fs})
    : _fs = fs ?? LocalFilesystem();

  final String journalRoot;
  final Filesystem _fs;

  static final Map<String, Future<void>> _seatLocks = {};
  static final Map<String, _SeatCursor> _cursors = {};

  static const _tailWindows = <int>[
    4 * 1024,
    64 * 1024,
    256 * 1024,
    1024 * 1024 + 8192,
  ];
  static const _readChunkBytes = 64 * 1024;

  @visibleForTesting
  static int get activeSeatLockCount => _seatLocks.length;

  @visibleForTesting
  static void debugResetSeatState() {
    _seatLocks.clear();
    _cursors.clear();
  }

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
      final path = _fileFor(draft.seat);
      await _fs.ensureDir(_fs.pathContext.dirname(path));
      final sequence = await _lastSequence(path) + 1;
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
      final line = utf8.encode('${jsonEncode(_encode(event))}\n');
      final cursor = _cursors[path]!;
      final payload = cursor.needsNewline
          ? Uint8List.fromList([0x0A, ...line])
          : line;
      cursor.needsNewline = false;
      await _fs.appendBytes(path, payload);
      _noteAppend(path, sequence, payload.length);
      return event;
    });
  }

  @override
  Stream<RuntimeEventEnvelope> replay(
    RuntimeSeatKey seat, {
    int afterSequence = 0,
  }) async* {
    final path = _fileFor(seat);
    final stat = await _fs.stat(path);
    if (!stat.exists || !stat.isFile) return;
    final size = stat.size ?? 0;
    if (size <= 0) return;

    var start = 0;
    final cursor = _cursors[path];
    if (afterSequence > 0 &&
        cursor != null &&
        cursor.lineEndBytes.length >= afterSequence) {
      start = cursor.lineEndBytes[afterSequence - 1];
    }
    if (start >= size) return;

    await for (final event in _readEvents(
      path,
      seat: seat,
      start: start,
      size: size,
      cursor: cursor ?? _cursors.putIfAbsent(path, _SeatCursor.new),
    )) {
      if (event.sequence > afterSequence) yield event;
    }
  }

  /// Each seat's journal lives at `{session}/{member}.jsonl`, so only that
  /// session's directory is scanned to recover its seats. Member ids are
  /// recovered from the filename encoding; journal bodies are not read.
  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) async {
    final sessionDir = _fs.pathContext.join(
      journalRoot,
      _pathSegment(sessionId),
    );
    final dirStat = await _fs.stat(sessionDir);
    if (!dirStat.exists || !dirStat.isDirectory) return const {};
    final seats = <RuntimeSeatKey>{};
    for (final entry in await _fs.listDir(sessionDir)) {
      if (entry.isDirectory || !entry.name.endsWith('.jsonl')) continue;
      final memberId = _fromPathSegment(
        entry.name.substring(0, entry.name.length - '.jsonl'.length),
      );
      if (memberId == null || memberId.isEmpty) continue;
      final path = _fs.pathContext.join(sessionDir, entry.name);
      final fileStat = await _fs.stat(path);
      if (!fileStat.exists || !fileStat.isFile || (fileStat.size ?? 0) <= 0) {
        continue;
      }
      seats.add(RuntimeSeatKey(sessionId: sessionId, memberId: memberId));
    }
    return seats;
  }

  Future<int> _lastSequence(String path) async {
    final stat = await _fs.stat(path);
    final size = stat.exists && stat.isFile ? (stat.size ?? 0) : 0;
    if (size <= 0) {
      _cursors[path] = _SeatCursor();
      return 0;
    }
    final cursor = _cursors[path];
    if (cursor != null && cursor.fileBytes == size) {
      return cursor.lastSequence;
    }
    final tail = await _readLastSequence(path, size);
    _cursors[path] = _SeatCursor(
      lastSequence: tail.sequence,
      fileBytes: size,
      needsNewline: !tail.endsWithNewline,
    );
    return tail.sequence;
  }

  void _noteAppend(String path, int sequence, int lineBytes) {
    final cursor = _cursors.putIfAbsent(path, _SeatCursor.new);
    cursor.lastSequence = sequence;
    cursor.fileBytes += lineBytes;
    if (cursor.lineEndBytes.length == sequence - 1) {
      cursor.lineEndBytes.add(cursor.fileBytes);
    }
  }

  Future<({int sequence, bool endsWithNewline})> _readLastSequence(
    String path,
    int size,
  ) async {
    ({int sequence, bool endsWithNewline}) from(List<int> bytes, bool wholeFile) {
      final sequence = _lastSequenceIn(bytes, wholeFile: wholeFile);
      return (
        sequence: sequence ?? 0,
        endsWithNewline: bytes.isNotEmpty && bytes.last == 0x0A,
      );
    }

    for (final window in _tailWindows) {
      final wholeFile = size <= window;
      final start = wholeFile ? 0 : size - window;
      final bytes = await _fs.readBytesRange(path, start, size - start);
      final parsed = _lastSequenceIn(
        bytes ?? const <int>[],
        wholeFile: wholeFile,
      );
      if (parsed != null) {
        return from(bytes ?? const <int>[], wholeFile);
      }
    }
    final bytes = await _fs.readBytesRange(path, 0, size) ?? const <int>[];
    return from(bytes, true);
  }

  Stream<RuntimeEventEnvelope> _readEvents(
    String path, {
    required RuntimeSeatKey seat,
    required int start,
    required int size,
    required _SeatCursor cursor,
  }) async* {
    var offset = start;
    var recordEnd = start;
    final pending = BytesBuilder(copy: false);
    while (offset < size) {
      final take = math.min(_readChunkBytes, size - offset);
      final slice = await _fs.readBytesRange(path, offset, take);
      if (slice == null || slice.isEmpty) break;
      offset += slice.length;
      pending.add(slice);
      final data = pending.takeBytes();
      var consumed = 0;
      for (var i = 0; i < data.length; i++) {
        if (data[i] != 0x0A) continue;
        final line = data.sublist(consumed, i);
        consumed = i + 1;
        recordEnd += line.length + 1;
        final event = _eventFromLine(line, seat);
        if (event != null) {
          if (cursor.lineEndBytes.length == event.sequence - 1) {
            cursor.lineEndBytes.add(recordEnd);
          }
          yield event;
        }
      }
      if (consumed < data.length) {
        pending.add(data.sublist(consumed));
      }
    }
  }
}

final class _SeatCursor {
  _SeatCursor({
    this.lastSequence = 0,
    this.fileBytes = 0,
    this.needsNewline = false,
  });

  int lastSequence;
  int fileBytes;
  bool needsNewline;
  final List<int> lineEndBytes = [];
}

int? _lastSequenceIn(List<int> bytes, {required bool wholeFile}) {
  if (bytes.isEmpty) return 0;
  var end = bytes.length;
  if (bytes[end - 1] == 0x0A) end--;
  while (end > 0) {
    var start = 0;
    var sawBreak = false;
    for (var i = end - 1; i >= 0; i--) {
      if (bytes[i] != 0x0A) continue;
      start = i + 1;
      sawBreak = true;
      break;
    }
    if (!wholeFile && !sawBreak) return null;
    if (end > start) {
      final event = _eventFromLine(bytes.sublist(start, end), null);
      if (event != null) return event.sequence;
    }
    if (!sawBreak) return 0;
    end = start - 1;
  }
  return 0;
}

RuntimeEventEnvelope? _eventFromLine(List<int> line, RuntimeSeatKey? seat) {
  if (line.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(line));
    if (decoded is! Map) return null;
    final event = _decode(Map<String, Object?>.from(decoded));
    if (event == null) return null;
    if (seat != null && event.seat != seat) return null;
    return event;
  } on FormatException {
    return null;
  }
}

String _pathSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String? _fromPathSegment(String segment) {
  if (segment.isEmpty) return null;
  var padded = segment;
  switch (padded.length % 4) {
    case 1:
      return null;
    case 2:
      padded = '$padded==';
    case 3:
      padded = '$padded=';
  }
  try {
    return utf8.decode(base64Url.decode(padded));
  } on FormatException {
    return null;
  }
}

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
