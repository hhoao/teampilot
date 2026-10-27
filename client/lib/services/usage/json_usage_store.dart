import 'dart:convert';

import '../../models/session_usage.dart';
import '../../utils/lock_pool.dart';
import '../io/filesystem.dart';
import 'usage_store.dart';

final class _UsageRecord {
  const _UsageRecord(this.event, this.revision);

  final SessionUsageEvent event;
  final int revision;
}

/// Append-only JSONL store with an in-memory latest-revision index.
///
/// A correction is another line with the same `requestId` and a higher `rev`.
/// The file is never rewritten, so a crash can only leave an extra line, never
/// a torn earlier record. JSONL (not SQLite) keeps this usable on an SSH home
/// plane where `sqlite3` cannot open an SFTP path.
class JsonUsageStore implements UsageStore {
  JsonUsageStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;
  final LockPool _locks = LockPool();

  Map<String, _UsageRecord>? _index;
  String? _fingerprint;
  var _lineCount = 0;
  var _sizeBytes = 0;
  bool _needsLeadingNewline = false;

  Future<String> _fileFingerprint() async {
    final stat = await _fs.stat(_path);
    _sizeBytes = stat.size ?? 0;
    return '${stat.size ?? -1}:${stat.mtime?.millisecondsSinceEpoch ?? -1}';
  }

  Future<Map<String, _UsageRecord>> _load() async {
    final fingerprint = await _fileFingerprint();
    final cached = _index;
    if (cached != null && _fingerprint == fingerprint) return cached;

    final raw = await _fs.readString(_path);
    final index = <String, _UsageRecord>{};
    var lineCount = 0;
    _needsLeadingNewline = raw != null && raw.isNotEmpty && !raw.endsWith('\n');
    if (raw != null) {
      for (final line in const LineSplitter().convert(raw)) {
        lineCount++;
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          final revision = (decoded['rev'] as num?)?.toInt() ?? 0;
          final eventRaw = decoded['event'];
          if (eventRaw is! Map) continue;
          final event = SessionUsageEvent.fromJson(
            Map<String, Object?>.from(eventRaw),
          );
          if (event.requestId.isEmpty) continue;
          final previous = index[event.requestId];
          if (previous == null || revision >= previous.revision) {
            index[event.requestId] = _UsageRecord(event, revision);
          }
        } on Object {
          continue;
        }
      }
    }
    _index = index;
    _lineCount = lineCount;
    _fingerprint = fingerprint;
    return index;
  }

  @override
  Future<UsageAppendResult> upsert(Iterable<SessionUsageEvent> events) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final next = Map<String, _UsageRecord>.of(current);
      final buffer = StringBuffer();
      var inserted = 0;
      var updated = 0;
      var skipped = 0;

      if (_needsLeadingNewline && events.isNotEmpty) {
        buffer.write('\n');
      }

      for (final event in events) {
        if (event.requestId.isEmpty || !event.hasBillableTokens) {
          skipped++;
          continue;
        }
        final previous = next[event.requestId];
        if (previous == null) {
          next[event.requestId] = _UsageRecord(event, 0);
          buffer.writeln(jsonEncode({'rev': 0, 'event': event.toJson()}));
          inserted++;
          continue;
        }
        if (!_shouldReplace(previous.event, event)) {
          skipped++;
          continue;
        }
        final revision = previous.revision + 1;
        next[event.requestId] = _UsageRecord(event, revision);
        buffer.writeln(jsonEncode({'rev': revision, 'event': event.toJson()}));
        updated++;
      }

      if (buffer.isNotEmpty) {
        final text = buffer.toString();
        try {
          await _fs.appendString(_path, text);
        } on Object {
          // The in-memory index may no longer match a partially appended file.
          _index = null;
          _fingerprint = null;
          _lineCount = 0;
          rethrow;
        }
        _index = next;
        _lineCount += '\n'.allMatches(text).length;
        _needsLeadingNewline = false;
        _fingerprint = await _fileFingerprint();
      }
      return UsageAppendResult(
        inserted: inserted,
        updated: updated,
        skipped: skipped,
      );
    });
  }

  static bool _shouldReplace(
    SessionUsageEvent previous,
    SessionUsageEvent incoming,
  ) {
    if (incoming.isFinal && !previous.isFinal) return true;
    if (!incoming.isFinal && previous.isFinal) return false;
    if (incoming.costMicroUsd != null &&
        incoming.costMicroUsd != previous.costMicroUsd) {
      return true;
    }
    if (incoming.model.isNotEmpty && incoming.model != previous.model) {
      return true;
    }
    return incoming.outputTokens > previous.outputTokens;
  }

  Future<UsageStoreStats> stats() async {
    final index = await _load();
    return UsageStoreStats(
      lineCount: _lineCount,
      eventCount: index.length,
      sizeBytes: _sizeBytes,
    );
  }

  /// Rewrites the file with the latest revision per request id.
  ///
  /// When [retainAfterMs] is set, events older than that timestamp are dropped.
  /// The rewrite is atomic; failures leave the old file intact.
  Future<UsageCompactResult> compact({int? retainAfterMs}) {
    return _locks.synchronized(_path, () async {
      final current = await _load();
      final beforeLines = _lineCount;
      final next = <String, _UsageRecord>{};
      for (final entry in current.entries) {
        final event = entry.value.event;
        if (retainAfterMs != null && event.timestampMs < retainAfterMs) {
          continue;
        }
        next[entry.key] = _UsageRecord(event, 0);
      }
      final buffer = StringBuffer();
      for (final record in next.values) {
        buffer.writeln(jsonEncode({'rev': 0, 'event': record.event.toJson()}));
      }
      await _fs.atomicWrite(_path, buffer.toString());
      _index = next;
      _lineCount = next.length;
      _needsLeadingNewline = false;
      _fingerprint = await _fileFingerprint();
      return UsageCompactResult(
        beforeLines: beforeLines,
        afterEvents: next.length,
        removedLines: beforeLines - next.length,
        removedEvents: current.length - next.length,
      );
    });
  }

  Future<UsageCompactResult?> maybeCompact({
    int threshold = 20000,
    int? retainAfterMs,
  }) async {
    await _load();
    if (_lineCount < threshold) return null;
    return compact(retainAfterMs: retainAfterMs);
  }

  @override
  Future<List<SessionUsageEvent>> readLatest() async {
    final index = await _load();
    final events = [for (final record in index.values) record.event];
    events.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return events;
  }
}
