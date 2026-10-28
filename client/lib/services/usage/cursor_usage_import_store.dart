import 'dart:convert';

import '../../models/cursor_usage_import.dart';
import '../../models/session_usage.dart';
import '../io/filesystem.dart';

/// Account-level Cursor dashboard usage, kept apart from the per-session
/// scanner so imports can replace/merge without rewriting `events.jsonl`.
final class CursorUsageImportStore {
  CursorUsageImportStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;

  Future<CursorUsageImportSnapshot> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) {
      return CursorUsageImportSnapshot.empty;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CursorUsageImportSnapshot.empty;
      return CursorUsageImportSnapshot.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return CursorUsageImportSnapshot.empty;
    }
  }

  Future<CursorUsageImportSnapshot> save(
    CursorUsageImportSnapshot snapshot,
  ) async {
    await _fs.ensureDir(_fs.pathContext.dirname(_path));
    await _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
    return snapshot;
  }

  Future<CursorUsageImportResult> merge({
    required List<SessionUsageEvent> events,
    required CursorUsageOrigin origin,
    required int startMs,
    required int endMs,
    required int nowMs,
    String account = '',
  }) async {
    final previous = await load();
    final records = previous.records.toList();
    if (origin == CursorUsageOrigin.sync) {
      records.removeWhere(
        (record) =>
            record.origin == CursorUsageOrigin.sync &&
            record.account == account &&
            record.event.timestampMs >= startMs &&
            record.event.timestampMs <= endMs,
      );
    }

    final byId = <String, CursorUsageRecord>{
      for (final record in records) record.event.requestId: record,
    };
    var inserted = 0;
    var updated = 0;
    var skipped = 0;
    for (final event in events) {
      if (event.requestId.isEmpty || !event.hasBillableTokens) {
        skipped++;
        continue;
      }
      final existing = byId[event.requestId];
      if (existing != null) {
        if (existing.origin == CursorUsageOrigin.manual &&
            origin == CursorUsageOrigin.sync) {
          skipped++;
          continue;
        }
        if (existing.origin == origin &&
            existing.account == account &&
            existing.event == event) {
          skipped++;
          continue;
        }
        updated++;
      } else {
        inserted++;
      }
      byId[event.requestId] = CursorUsageRecord(
        event: event,
        origin: origin,
        account: origin == CursorUsageOrigin.sync ? account : '',
      );
    }

    final next = CursorUsageImportSnapshot(
      records: byId.values.toList(growable: false),
      coverage: _mergeCoverage(
        previous.coverage,
        CursorUsageCoverage(
          startMs: startMs,
          endMs: endMs,
          origin: origin,
          account: origin == CursorUsageOrigin.sync ? account : '',
        ),
      ),
      lastImportAtMs: origin == CursorUsageOrigin.manual
          ? nowMs
          : previous.lastImportAtMs,
      lastSyncAtMs: origin == CursorUsageOrigin.sync
          ? nowMs
          : previous.lastSyncAtMs,
      lastSyncAccount: origin == CursorUsageOrigin.sync
          ? account
          : previous.lastSyncAccount,
    );
    await save(next);
    return CursorUsageImportResult(
      status: next.status,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      total: events.length,
    );
  }

  Future<void> clear() => save(CursorUsageImportSnapshot.empty);

  Future<CursorUsageImportStatus> status() async => (await load()).status;

  Future<List<SessionUsageEvent>> loadEvents() async {
    final snapshot = await load();
    return snapshot.events
        .where((event) => event.sessionId == cursorImportedSessionId)
        .toList(growable: false);
  }
}

List<CursorUsageCoverage> _mergeCoverage(
  List<CursorUsageCoverage> existing,
  CursorUsageCoverage incoming,
) {
  final grouped = <String, List<CursorUsageCoverage>>{};
  for (final range in [...existing, incoming]) {
    final key = '${range.origin.value}\u0000${range.account}';
    grouped.putIfAbsent(key, () => []).add(range);
  }
  final out = <CursorUsageCoverage>[];
  for (final ranges in grouped.values) {
    ranges.sort((a, b) => a.startMs.compareTo(b.startMs));
    var start = ranges.first.startMs;
    var end = ranges.first.endMs;
    for (final range in ranges.skip(1)) {
      if (range.startMs <= end + 1) {
        if (range.endMs > end) end = range.endMs;
      } else {
        out.add(
          CursorUsageCoverage(
            startMs: start,
            endMs: end,
            origin: ranges.first.origin,
            account: ranges.first.account,
          ),
        );
        start = range.startMs;
        end = range.endMs;
      }
    }
    out.add(
      CursorUsageCoverage(
        startMs: start,
        endMs: end,
        origin: ranges.first.origin,
        account: ranges.first.account,
      ),
    );
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return List.unmodifiable(out);
}
