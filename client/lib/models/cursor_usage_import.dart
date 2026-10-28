import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'session_usage.dart';

/// Synthetic session label for account-level Cursor dashboard rows.
const cursorImportedSessionId = 'Cursor (imported)';

enum CursorUsageOrigin {
  manual('manual'),
  sync('sync');

  const CursorUsageOrigin(this.value);

  final String value;

  static CursorUsageOrigin fromJson(Object? raw) =>
      raw?.toString() == sync.value ? sync : manual;
}

@immutable
class CursorUsageRecord extends Equatable {
  const CursorUsageRecord({
    required this.event,
    required this.origin,
    this.account = '',
  });

  final SessionUsageEvent event;
  final CursorUsageOrigin origin;
  final String account;

  Map<String, Object?> toJson() => {
    'event': event.toJson(),
    'origin': origin.value,
    if (account.isNotEmpty) 'account': account,
  };

  factory CursorUsageRecord.fromJson(Map<String, Object?> json) {
    final raw = json['event'];
    return CursorUsageRecord(
      event: SessionUsageEvent.fromJson(
        raw is Map ? Map<String, Object?>.from(raw) : const {},
      ),
      origin: CursorUsageOrigin.fromJson(json['origin']),
      account: '${json['account'] ?? ''}',
    );
  }

  @override
  List<Object?> get props => [event, origin, account];
}

@immutable
class CursorUsageCoverage extends Equatable {
  const CursorUsageCoverage({
    required this.startMs,
    required this.endMs,
    required this.origin,
    this.account = '',
  });

  final int startMs;
  final int endMs;
  final CursorUsageOrigin origin;
  final String account;

  Map<String, Object?> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'origin': origin.value,
    if (account.isNotEmpty) 'account': account,
  };

  factory CursorUsageCoverage.fromJson(Map<String, Object?> json) =>
      CursorUsageCoverage(
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        origin: CursorUsageOrigin.fromJson(json['origin']),
        account: '${json['account'] ?? ''}',
      );

  @override
  List<Object?> get props => [startMs, endMs, origin, account];
}

@immutable
class CursorUsageImportSnapshot extends Equatable {
  const CursorUsageImportSnapshot({
    this.records = const [],
    this.coverage = const [],
    this.lastImportAtMs,
    this.lastSyncAtMs,
    this.lastSyncAccount = '',
  });

  static const empty = CursorUsageImportSnapshot();

  final List<CursorUsageRecord> records;
  final List<CursorUsageCoverage> coverage;
  final int? lastImportAtMs;
  final int? lastSyncAtMs;
  final String lastSyncAccount;

  CursorUsageImportStatus get status => CursorUsageImportStatus(
    eventCount: _dedupedEvents.length,
    lastImportAtMs: lastImportAtMs,
    lastSyncAtMs: lastSyncAtMs,
  );

  List<SessionUsageEvent> get events => _dedupedEvents;

  List<SessionUsageEvent> get _dedupedEvents {
    final byId = <String, SessionUsageEvent>{};
    final origins = <String, CursorUsageOrigin>{};
    for (final record in records) {
      final id = record.event.requestId;
      final previousOrigin = origins[id];
      if (previousOrigin == null ||
          (record.origin == CursorUsageOrigin.manual &&
              previousOrigin == CursorUsageOrigin.sync)) {
        byId[id] = record.event;
        origins[id] = record.origin;
      }
    }
    final out = byId.values.toList(growable: false)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return out;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'records': [for (final record in records) record.toJson()],
    'coverage': [for (final range in coverage) range.toJson()],
    if (lastImportAtMs != null) 'lastImportAtMs': lastImportAtMs,
    if (lastSyncAtMs != null) 'lastSyncAtMs': lastSyncAtMs,
    if (lastSyncAccount.isNotEmpty) 'lastSyncAccount': lastSyncAccount,
  };

  factory CursorUsageImportSnapshot.fromJson(Map<String, Object?> json) {
    final recordsRaw = json['records'];
    final coverageRaw = json['coverage'];
    return CursorUsageImportSnapshot(
      records: recordsRaw is List
          ? [
              for (final raw in recordsRaw)
                if (raw is Map)
                  CursorUsageRecord.fromJson(Map<String, Object?>.from(raw)),
            ]
          : const [],
      coverage: coverageRaw is List
          ? [
              for (final raw in coverageRaw)
                if (raw is Map)
                  CursorUsageCoverage.fromJson(Map<String, Object?>.from(raw)),
            ]
          : const [],
      lastImportAtMs: (json['lastImportAtMs'] as num?)?.toInt(),
      lastSyncAtMs: (json['lastSyncAtMs'] as num?)?.toInt(),
      lastSyncAccount: '${json['lastSyncAccount'] ?? ''}',
    );
  }

  @override
  List<Object?> get props => [
    records,
    coverage,
    lastImportAtMs,
    lastSyncAtMs,
    lastSyncAccount,
  ];
}

@immutable
class CursorUsageImportStatus extends Equatable {
  const CursorUsageImportStatus({
    this.eventCount = 0,
    this.lastImportAtMs,
    this.lastSyncAtMs,
  });

  final int eventCount;
  final int? lastImportAtMs;
  final int? lastSyncAtMs;

  bool get hasData => eventCount > 0;

  int? get lastUpdatedAtMs {
    final values = [lastImportAtMs, lastSyncAtMs].whereType<int>();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  @override
  List<Object?> get props => [eventCount, lastImportAtMs, lastSyncAtMs];
}

@immutable
class CursorUsageImportResult extends Equatable {
  const CursorUsageImportResult({
    required this.status,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.total = 0,
  });

  final CursorUsageImportStatus status;
  final int inserted;
  final int updated;
  final int skipped;
  final int total;

  @override
  List<Object?> get props => [status, inserted, updated, skipped, total];
}
